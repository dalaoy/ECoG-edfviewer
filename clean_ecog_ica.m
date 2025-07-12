function clean_ecog_ica_matlab(input_mat_file, output_mat_file_prefix)
% clean_ecog_ica_matlab: 在MATLAB中直接对ECoG数据进行ICA伪迹去除。
%   专门用于去除肌电（EMG）伪迹。
%
%   input_mat_file:         预处理后的 .mat 文件路径，应包含 'concatenated_ecog' 和 'target_sampling_rate'。
%   output_mat_file_prefix: 保存的干净信号 .mat 文件的前缀名 (例如 'cleaned_ecog')。

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG ICA 伪迹去除脚本 (纯 MATLAB 版) 开始\n');
    fprintf('--------------------------------------------------\n');

    % 1. 加载数据
    fprintf('正在加载预处理数据: %s\n', input_mat_file);
    try
        loaded_data = load(input_mat_file);
    catch ME
        error('加载输入 .mat 文件失败: %s', ME.message);
    end

    if isfield(loaded_data, 'concatenated_ecog')
        ecog_data_raw = loaded_data.concatenated_ecog;
        fprintf('成功加载 ECoG 数据。维度: %s\n', mat2str(size(ecog_data_raw)));
    else
        error('输入 .mat 文件中未找到 ''concatenated_ecog'' 变量。');
    end

    if isfield(loaded_data, 'target_sampling_rate')
        srate = loaded_data.target_sampling_rate(1);
        fprintf('成功加载采样率: %g Hz\n', srate);
    else
        error('输入 .mat 文件中未找到 ''target_sampling_rate'' 变量。');
    end

    % 确保数据是 (通道数 x 采样点数)
    if size(ecog_data_raw, 1) > size(ecog_data_raw, 2) && size(ecog_data_raw, 2) < 200 % 假设通道数小于200
        ecog_data_raw = ecog_data_raw'; % 转置为 (通道数 x 采样点数)
        fprintf('数据已转置为 (通道数 x 采样点数)。\n');
    end
    
    nbchan = size(ecog_data_raw, 1);
    pnts = size(ecog_data_raw, 2);

    % 2. 数据预处理 for ICA
    % ICA 对数据通常有要求：零均值 (Zero Mean)
    fprintf('正在对数据进行零均值处理...\n');
    ecog_data_demeaned = bsxfun(@minus, ecog_data_raw, mean(ecog_data_raw, 2));

    % 3. 运行 ICA
    % 使用 MATLAB 的 rica (Randomized ICA) 函数，需要 Statistics and Machine Learning Toolbox
    fprintf('正在运行 ICA (使用 rica 函数)...\n');
    fprintf('这可能需要几分钟到几小时，取决于数据量和CPU性能。\n');
    
    % rica 返回 W (分离矩阵) 和 K (白化矩阵)
    % 独立成分 (ICs) = W * K * Data
    % 或者更直接地：ICs = (W * K) * Data_demeaned
    % 重构回原始空间：Reconstructed_Data = inv(W*K) * ICs
    
    % 注意：rica 函数的 API 是 ICs = rica(Data', numComponents)
    % Data' 是 (pnts x nbchan)，返回的 ICs 是 (pnts x numComponents)
    % W 矩阵是 (numComponents x nbchan)
    % ICs = (Data_demeaned' * W')' => ICs = W * Data_demeaned
    
    num_components = nbchan; % 计算与通道数相同数量的成分

    % ricacore function for lower versions (e.g. 2017a does not have rica)
    % [ica_weights, ica_sphere] = runica(ecog_data_demeaned); % If you have runica from EEGLAB
    % Or, if using rica (from Statistics and Machine Learning Toolbox)
    try
        % Mdl = rica(Data', numComponents) returns the trained rica model
        % Data must be observations-by-features (timepoints-by-channels)
        Mdl = rica(ecog_data_demeaned', num_components); 
        ica_components = Mdl.transform(ecog_data_demeaned'); % 得到 ICs (timepoints x num_components)
        ica_weights = Mdl.TransformWeights; % 得到分离矩阵 W (num_components x nbchan)
        % Mdl.TransformWeights is W*K, effectively.
        % So, ica_components = (W*K) * ecog_data_demeaned
        
        % In this case, ica_inv_weights (mixing matrix) would be inv(ica_weights)
        ica_inv_weights = inv(ica_weights); % 混合矩阵 (nbchan x num_components)

        fprintf('ICA 分析完成 (使用 rica)。\n');
    catch ME
        if (strcmp(ME.identifier, 'MATLAB:UndefinedFunction'))
            error('未找到 rica 函数。请确保已安装 Statistics and Machine Learning Toolbox，或者使用其他 ICA 实现 (例如，从 https://research.ics.aalto.fi/ica/fastica/ 下载 FastICA)。');
        else
            rethrow(ME);
        end
    end

    % 将独立成分转置为 (成分数 x 采样点数) 方便处理
    ica_components = ica_components'; % (num_components x pnts)

    % 4. 伪迹成分识别 (基于高频功率和峰度)
    fprintf('正在识别潜在的肌电伪迹成分...\n');
    
    artifact_ics_found = [];
    
    % 伪迹识别参数 - **请根据您的数据进行调整！**
    emg_freq_band = [30, 150]; % 肌电主要功率频段 (Hz)
    kurtosis_threshold = 10;   % 峰度阈值，通常EMG成分峰度很高 (>30 甚至 >100)
                              % 脑电成分峰度通常在 -1 到 3 之间
    power_ratio_threshold = 5; % 伪迹频段功率与总功率的比值阈值

    for ic = 1:num_components
        ic_data = ica_components(ic, :);
        
        % 检查高频功率 (使用 pwelch)
        [Pxx, F] = pwelch(ic_data, srate, srate/2, srate, srate); % 窗长 = 采样率 (1秒)
        
        % 找到肌电频段的索引
        emg_freq_indices = find(F >= emg_freq_band(1) & F <= emg_freq_band(2));
        total_power_indices = find(F >= 1 & F <= srate/2); % 整个有效频段
        
        if ~isempty(emg_freq_indices) && ~isempty(total_power_indices)
            emg_band_power = sum(Pxx(emg_freq_indices));
            total_ic_power = sum(Pxx(total_power_indices));
            
            % 计算峰度
            kurt = kurtosis(ic_data);
            
            % 判断是否为伪迹
            % 满足两个条件：高峰度和高频功率占比
            if kurt > kurtosis_threshold && (emg_band_power / total_ic_power) > power_ratio_threshold
                artifact_ics_found = [artifact_ics_found, ic];
                fprintf('  识别到伪迹成分 IC %d: 峰度 = %.2f, 频段 (%g-%g Hz) 功率占比 = %.2f\n', ...
                        ic, kurt, emg_freq_band(1), emg_freq_band(2), (emg_band_power / total_ic_power));
            end
        end
    end

    if isempty(artifact_ics_found)
        fprintf('未自动识别到明显的肌电伪迹成分。这可能意味着数据很干净，或者阈值设置过于严格。\n');
        cleaned_ecog_data = ecog_data_raw; % 如果没有识别到伪迹，则返回原始数据
    else
        fprintf('初步识别到以下潜在肌电伪迹成分 (IC): %s\n', mat2str(artifact_ics_found));
        
        % 5. 移除伪迹成分并重构信号
        % 创建一个所有成分的索引
        all_ics_indices = 1:num_components;
        % 找到非伪迹成分的索引
        non_artifact_ics = setdiff(all_ics_indices, artifact_ics_found);
        
        if isempty(non_artifact_ics)
            warning('所有独立成分都被标记为伪迹。无法重构数据。返回原始数据。');
            cleaned_ecog_data = ecog_data_raw;
        else
            fprintf('正在移除独立成分并重构信号...\n');
            
            % 重构：Reconstructed_Data = inv(W*K) * ICs
            % 这里的 ica_inv_weights 已经是 inv(W*K) (混合矩阵)
            % 移除成分意味着将对应成分的行在 ica_components 中置零
            
            ica_components_cleaned = ica_components;
            ica_components_cleaned(artifact_ics_found, :) = 0; % 将伪迹成分的时间序列置零
            
            % 重构回原始通道空间
            % Reconstructed_Data = ica_inv_weights * ica_components_cleaned + mean(ecog_data_raw, 2); (如果原始数据是去均值前)
            % 由于我们去均值了原始数据，重构后也要加回均值
            
            cleaned_ecog_data = (ica_inv_weights * ica_components_cleaned) + mean(ecog_data_raw, 2);
            fprintf('信号重构完成。\n');
        end
    end

    % 6. 保存干净的信号为新的 .mat 文件
    output_folder = fileparts(input_mat_file);
    output_mat_file = fullfile(output_folder, [output_mat_file_prefix, '.mat']);
    
    fprintf('正在保存干净信号到 .mat 文件: %s\n', output_mat_file);
    % 保存为 'concatenated_ecog' 变量名，方便后续使用
    concatenated_ecog = cleaned_ecog_data; % 命名以匹配之前的输出格式
    target_sampling_rate = srate; % 也保存采样率
    
    save(output_mat_file, 'concatenated_ecog', 'target_sampling_rate', '-v7.3'); % Use -v7.3 for large files
    
    fprintf('ECoG ICA 伪迹去除和保存完成。\n');
    fprintf('您可以在 GUI 中加载 %s 文件进行进一步分析。\n', output_mat_file);
    fprintf('--------------------------------------------------\n');
end