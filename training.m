%--------------------------------------------------------------------------
%   Once the training set has been created, this script trains the
%   classifiers.
%--------------------------------------------------------------------------
function training
    
    %----------------------------------------------------------------------
    % NESTED FUNCTIONS
    %----------------------------------------------------------------------
    
    %
    % Trova il miglior classificatore debole
    %
    function find_best_weak_classifier(X,Y,feat_cnt,group)
        filename = sprintf('./tmp/featgroup_%d.mat', group);
        if(feat_cnt == 1)
            fprintf('.');
        end
        
        % Se esiste gi� un file del gruppo di features corrente
        if(exist(filename, 'file'))
            % Carico il gruppo da file
            load(filename, 'group');
        else
            % Inizializzo un gruppo vuoto
            group = [];
        end
        
        % Se il gruppo contiene gi� la feature che voglio calcolare
        if(size(group,1) >= feat_cnt)
            % carico i valori della feature dal gruppo
            cur_feat_values = group(feat_cnt,:);
        else
            % La feature calcolata per tutte le immagini del training set
            cur_feat_values = zeros(1,tot_examples);

            % Calcolo la feature per tutte le immagini
            for j=1:tot_examples
                cur_feat_values(j) = rectfeature(integral_images(:,:,j),X,Y);
            end
            
            % Inserisco la feature nel gruppo
            group(feat_cnt,:) = cur_feat_values;
            
            % Salvo il gruppo
            save(filename, 'group');
        end
        
        % Inizializzo una lista ordinata di immagini
        [sorted_examples,sorted_indices] = sort(cur_feat_values);
        
        % Inizializzo S+ e S-
        Spos = 0;
        Sneg = 0;
        
        % Per ogni immagine
        for j=1:tot_examples
            % Se l'immagine non � ancora stata scartata
            if(positives(sorted_indices(j)))
                
                % Calcola questa formula:
                %
                % e = min(S+ + (T- - S-), S- + (T+ - S+))
                %         |____________|  |____________|
                %                |               |
                %               p=-1            p=1
                
                e1 = Spos + (Tneg - Sneg);
                e2 = Sneg + (Tpos - Spos);
                
                if e1 < e2
                    p = -1;
                    eTmp = e1;
                else
                    p = 1;
                    eTmp = e2;
                end
                
                % Se l'errore � minore di quelli calcolati
                % precedentemente, salva il valore corrente come valore
                % soglia, e salva il weak_classifier.
                if eTmp < e
                    e = eTmp;
                    weak_classifiers(weak_cnt).X = X;
                    weak_classifiers(weak_cnt).Y = Y;
                    weak_classifiers(weak_cnt).p = p;
                    weak_classifiers(weak_cnt).threshold = sorted_examples(j);
                end
                
                if sorted_indices(j) > tot_pos
                    Sneg = Sneg + weights(sorted_indices(j));
                else
                    Spos = Spos + weights(sorted_indices(j));
                end
            end
        end
    end
    
    %
    % Conta le features
    %
    function fcnt_increment(X,Y,feat_cnt, grp)
        tot_features = tot_features + 1;
    end

    %
    % Questa funzione conta i falsi positivi rimasti
    %
    function fp = false_positives
        fp = sum(positives(tot_pos+1:tot_examples));
    end
    
    %
    % Questa funzione conta i falsi negativi rimasti
    %
    function fn = false_negatives
        fn = tot_pos - sum(positives(1:tot_pos));
    end
    
    %----------------------------------------------------------------------
    % TRAINING ALGORITHM
    %----------------------------------------------------------------------

    IMSIZE = 24;            % The dimension of each image of the training set.
    FEAT_PER_GROUP = 100;    % The number of Haar-like features per group

    %
    % read all the images from the training set
    %
    fprintf('reading positive images from the training set...\n');
    original_positives = imreadall('img\training-set\faces\', IMSIZE, IMSIZE);
    fprintf('positive images read: %d\n', size(original_positives,3));
    fprintf('reading negative images from the training set...\n');
    original_negatives = imreadall('img\training-set\not-faces\', IMSIZE, IMSIZE);
    fprintf('negative images read: %d\n', size(original_negatives,3));

    %
    % initialize useful variables
    %
    tot_pos = size(original_positives,3);                           % Numero di esempi positivi
    tot_neg = size(original_negatives,3);                           % Numero di esempi negativi
    tot_examples = tot_pos + tot_neg;                               % Numero totale di esempi
    integral_images = zeros(IMSIZE+1, IMSIZE+1, tot_pos + tot_neg); % Gli esempi
    
    %
    % calculate the integral images
    %
    fprintf('calculating the integral images...\n');
    for i=1:tot_pos
        integral_images(:,:,i) = ii(original_positives(:,:,i));
    end
    for i=tot_pos+1:tot_examples
        integral_images(:,:,i) = ii(original_negatives(:,:,i-tot_pos));
    end
    fprintf('integral images calculated\n');
    
    %
    % Count the number of features
    %
    fprintf('counting number of features for a window of %dx%d...\n', IMSIZE, IMSIZE);
    tot_features = 0;
    foreachfeature(IMSIZE, @fcnt_increment);
    fprintf('counted %d Haar-like features\n', tot_features);
    
    %
    % Inizializzo le variabili
    %
    strong_cnt = 0;                                                     % Numero del classificatore forte corrente
    positives = ones(1, tot_examples);                                  % Array che contrassegna gli esempi considerati positivi dall'algoritmo
    strong_classifiers = struct('weak_classifiers', 0);                 % Gli strong classifiers della cascata
    
    fprintf('### training started! ###\n');
    fprintf('Keep calm and do anything else: this will take a very long time...\n');
    tic;
    % Finch� ho falsi positivi
    while false_positives > 0
        strong_cnt = strong_cnt + 1;
        
        % Inizializzo variabili per il ciclo
        weak_cnt = 0;                                                           % Numero del classificatore debole corrente
        neg_pruned = 0;                                                         % Numero di esempi negativi potati dal classificatore forte
        pos_approved = 0;                                                       % Numero di esempi positivi approvati dal classificatore forte
        neg_left = false_positives;                                             % Numero di esempi negativi ancora da potare
        pos_left = tot_pos - false_negatives;                                   % Numero di esempi positivi rimasti illesi
        weak_classifiers = struct('X',0,'Y',0,'p',0,'threshold',0, 'alpha',0);  % I weak classifiers dello strong classifier corrente
        
        % Inizializzo i pesi
        weights(1:tot_pos) = 1/(2*pos_left);
        weights(tot_pos+1:tot_examples) = 1/(2*neg_left);
        
        fprintf('*** computing cascade stage n. %d ***\n', strong_cnt); 
        % Finch� il numero di negativi potati � meno del 50%, ciclo le
        while(neg_pruned < neg_left / 2)
            weak_cnt = weak_cnt + 1;            % Numero del classificatore debole corrente
            fprintf('--- selecting the weak classifier n. %d for this stage... ---\n', weak_cnt);
            
            % Normalizzo i pesi rispetto agli esempi positivi rimasti
            weights = weights./sum(weights .* positives);
            
            % Inizializzo T+ e T- al loro valore (che non cambier� fino al prossimo ciclo)
            Tpos = sum(positives(1:tot_pos).*weights(1:tot_pos));
            Tneg = sum(positives(tot_pos+1:tot_examples).*weights(tot_pos+1:tot_examples));
            
            % Inizializza le variabili per trovare l'errore minimo
            weak_classifiers(weak_cnt).p = 0;
            e = inf;
            
            % Trova il miglior classificatore debole rispetto al peso
            foreachfeature(IMSIZE, @find_best_weak_classifier, FEAT_PER_GROUP);
            
            % Aggiorno i pesi
            beta = e/(1-e);
            for i = 1:tot_examples
                if positives(i) ~= 1
                    continue;
                end
                cur_feat = weak_classifiers(weak_cnt);
                pos = weak_classify(integral_images(:,:,i), cur_feat.X, cur_feat.Y, cur_feat.p, cur_feat.threshold);
                if i <= tot_pos && pos || i > tot_pos && ~pos
                    weights(i) = weights(i) * beta;
                end
            end
            
            fprintf('\nweak classifier chosen:\n- X: [');
            fprintf(' %d', cur_feat.X);
            fprintf(' ]\n- Y: [');
            fprintf(' %d', cur_feat.Y);
            fprintf(' ]\n- polarity: %d\n- threshold: %d\n', cur_feat.p, cur_feat.threshold);
            
            % Imposta le variabili per lo strong classifier
            weak_classifiers(weak_cnt).alpha = log(1/beta);
            
            fprintf('testing the strong classifier (composed by %d weak class.)...\n', weak_cnt);
            % Testa lo strong classifier sulle immagini negative
            pruned = [];
            approved = [];
            for i = 1:tot_examples
                if strong_classify(integral_images(:,:,i),weak_classifiers)
                    if positives(i)
                        continue;
                    end
                    approved = [approved i];
                    if i <= tot_pos
                        pos_approved = pos_approved + 1;
                    end
                else
                    if positives(i) ~= 1
                        continue;
                    end
                    pruned = [pruned i];
                    if i > tot_pos
                        neg_pruned = neg_pruned + 1;
                    end
                end
            end
            fprintf('- total samples marked as positive: %s\n', printpercent(length(approved), tot_examples));
            fprintf('- total samples marked as negative: %s\n', printpercent(length(pruned), tot_examples));
            fprintf('- negative samples pruned: %s\n', printpercent(neg_pruned, neg_left));
            fprintf('- false negatives: %s\n', printpercent(false_negatives, tot_examples - sum(positives)));
            fprintf('- false positives: %s\n', printpercent(false_positives, sum(positives)));
        end
        fprintf('\n');
        
        % Applico le modifiche alle immagini
        positives(pruned) = 0;
        positives(approved) = 1;
        
        % Aggiungo lo strong classifier risultante alla cascata
        strong_classifiers(strong_cnt).weak_classifiers = weak_classifiers;
    end
    toc
    save ('classifier_cascade.mat', 'strong_classifiers');
end