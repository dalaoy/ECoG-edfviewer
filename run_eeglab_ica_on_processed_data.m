function run_eeglab_ica_on_processed_data(input_mat_file, output_set_filename_prefix)
% run_eeglab_ica_on_processed_data 从预处理的.mat文件执行EEGLAB的ICA分析。
%
%   input_mat_file:           预处理后的 .mat 文件路径，应包含 'concatenated_ecog' 和 'target_sampling_rate'。
%   output_set_filename_prefix: 保存的EEGLAB .set文件的前缀名 (例如 'my_ica_data')。

    if nargin < 2
        error('请提供输入 .mat 文件路径和输出 .set 文件前缀。');
    end

    fprintf('--------------------------------------------------\n');
    fprintf('EEGLAB ICA 分析脚本开始\n');
    fprintf('--------------------------------------------------\n');

    % 1. 加载您的预处理数据
    fprintf('正在加载预处理数据: %s\n', input_mat_file);
    try
        loaded_data = load(input_mat_file);
    catch ME
        error('加载输入 .mat 文件失败: %s', ME.message);
    end

    if isfield(loaded_data, 'concatenated_ecog')
        data_to_process = loaded_data.concatenated_ecog;
        fprintf('成功加载 ECoG 数据。维度: %s\n', mat2str(size(data_to_process)));
    else
        error('输入 .mat 文件中未找到 ''concatenated_ecog'' 变量。');
    end

    if isfield(loaded_data, 'target_sampling_rate')
        srate = loaded_data.target_sampling_rate(1);
        fprintf('成功加载采样率: %g Hz\n', srate);
    else
        error('输入 .mat 文件中未找到 ''target_sampling_rate'' 变量。');
    end

    % 2. 创建 EEGLAB EEG 结构体
    fprintf('正在创建 EEGLAB EEG 结构体...\n');
    EEG = eeg_emptyset(); % 创建一个空的EEGLAB EEG结构体

    % 确保数据是 (通道数 x 采样点数)
    if size(data_to_process, 1) > size(data_to_process, 2) && size(data_to_process, 2) < 200 % 假设通道数小于200
        data_to_process = data_to_process'; % 转置为 EEGLAB 要求的格式
        fprintf('数据已转置为 (通道数 x 采样点数)。\n');
    end
    
    EEG.data = data_to_process;
    EEG.srate = srate;
    EEG.nbchan = size(EEG.data, 1);
    EEG.pnts = size(EEG.data, 2);
    EEG.trials = 1; % 连续数据视为1个试次
    EEG.xmin = 0;
    EEG.xmax = (EEG.pnts - 1) / EEG.srate;
    EEG.times = (0:EEG.pnts-1) / EEG.srate;
    EEG.setname = sprintf('%s_ICA', output_set_filename_prefix);
    EEG.filename = [output_set_filename_prefix, '.set'];
    EEG.filepath = fileparts(input_mat_file); % 将结果保存到与输入文件相同的目录
    
    fprintf('EEG 结构体创建完成。开始数据一致性检查...\n');
    EEG = eeg_checkset(EEG); % EEGLAB 内部数据一致性检查
    if isempty(EEG.data)
        error('EEG 结构体数据为空，检查数据加载。');
    end
    
    % 可选：添加通道位置信息 (如果已知的话)
    % 这一步非常重要，它能帮助你在 EEGLAB 中可视化成分的地形图，从而更好地判断伪迹。
    % 如果你有一个 .locs 或 .sfp 文件，可以在这里加载。
    % 假设你的电极是64通道的，并且你知道一个默认的64通道电极文件 (例如，你的自定义文件 rat_64ch_locs.locs)
    % 如果没有，EEGLAB会生成一个默认的圆形布局，或者你可以在EEGLAB GUI中手动导入。
    %
    % % 示例：加载通道位置文件（请根据您的实际文件路径和文件名修改）
    % % EEGLAB 通常使用 .locs 或 .sfp 格式
    % try
    %     fprintf('尝试加载通道位置信息...\n');
    %     EEG.chanlocs = readlocs('path/to/your/rat_64ch_locs.locs'); % <-- 请替换为你的实际通道位置文件路径
    %     EEG = eeg_checkset(EEG);
    %     fprintf('通道位置信息加载成功。\n');
    % catch ME_locs
    %     warning('无法加载通道位置文件 (%s)。您可以在EEGLAB GUI中手动导入。', ME_locs.message);
    % end


    % 3. 运行 ICA
    fprintf('正在运行 ICA (Infomax 算法，通常需要较长时间)...\n');
    fprintf('这可能需要几分钟到几小时，取决于数据量和CPU性能。\n');
    
    % 使用 pop_runica
    % 'icatype', 'runica': 使用默认的 Infomax 算法
    % 'extended', 1: 使用扩展ICA，可以更好地处理超高斯（如伪迹）和亚高斯分布（如脑电）的成分
    % 'pca', EEG.nbchan: 默认不对数据进行PCA降维，所有成分都将被计算
    %                   如果你有非常多通道或数据非常长，可以考虑先进行PCA降维，
    %                   例如 'pca', 0.99 (保留99%方差) 或 'pca', 60 (保留60个成分)
    
    [EEG, ~] = pop_runica(EEG, 'icatype', 'runica', 'extended', 1, 'pca', EEG.nbchan);
    
    fprintf('ICA 分析完成。独立成分已计算。\n');

    % 4. 可选：尝试初步的伪迹成分识别 (基于高频功率或异常大值)
    % **警告：这只是一个初步的自动识别，强烈建议人工检查！**
    % EMG 成分通常在高频（例如 30Hz 以上）具有显著功率，并且其时间序列可能显示出大而快的波动。
    
    artifact_ics = [];
    fprintf('正在尝试初步自动识别伪迹成分...\n');
    
    % 遍历每个独立成分
    for ic = 1:EEG.nbchan
        ic_data = EEG.icaact(ic, :); % 独立成分的时间序列
        
        % 检查高频功率 (例如 30Hz-100Hz 频段)
        % pwelch 计算功率谱密度
        [Pxx, F] = pwelch(ic_data, EEG.srate, EEG.srate/2, EEG.srate, EEG.srate); % 窗长=采样率，即1秒
        
        % 找到高频段 (例如 30Hz 以上)
        high_freq_indices = find(F >= 30 & F <= 100); 
        
        if ~isempty(high_freq_indices)
            high_freq_power = sum(Pxx(high_freq_indices));
            
            % 简单的阈值判断：如果高频功率非常高（需要根据数据特性调整阈值）
            % 例如，如果超过所有成分高频功率平均值的 N 倍，或者超过某个绝对值
            % 这里使用一个相对阈值作为示例，实际应用中需要调整
            % 假设我们认为高频功率超过中位数20倍可能是伪迹 (非常粗略)
            % 或者直接基于成分的时间序列的幅值标准差或峰度（Kurtosis）
            
            % 鲁棒性判断: 考虑成分的峰度 (Kurtosis)
            % 脑电信号通常是非高斯分布，但EMG信号通常有非常尖锐的峰值，峰度会很高。
            kurt = kurtosis(ic_data);
            
            % 设置一个启发式阈值来标记潜在伪迹
            % 经验阈值：峰度 > 10-20 通常可能是伪迹。高频功率也需要高。
            if kurt > 20 && high_freq_power > mean(Pxx) * 100 % 这是一个非常粗略的示例阈值，需根据经验调整
                artifact_ics = [artifact_ics, ic];
            end
        end
    end
    
    if ~isempty(artifact_ics)
        fprintf('初步识别到潜在伪迹成分 (IC): %s\n', mat2str(artifact_ics));
        choice = questdlg(sprintf('脚本初步识别到以下潜在伪迹成分: %s。\n是否要自动从数据中移除这些成分？\n(强烈建议在EEGLAB GUI中进行人工检查和确认！)', mat2str(artifact_ics)), ...
                          'ICA 伪迹移除确认', '是', '否', '否');
        if strcmp(choice, '是')
            fprintf('正在移除独立成分: %s\n', mat2str(artifact_ics));
            EEG = pop_subcomp(EEG, artifact_ics, 0); % 移除选定成分
            fprintf('独立成分移除完成。\n');
        else
            fprintf('用户选择不自动移除成分。请在EEGLAB GUI中手动检查。\n');
        end
    else
        fprintf('未初步识别到明显的伪迹成分。请在EEGLAB GUI中人工检查。\n');
    end

    % 5. 保存 ICA 结果为 EEGLAB .set 文件
    output_folder = fileparts(input_mat_file);
    output_set_file = fullfile(output_folder, [output_set_filename_prefix, '.set']);
    
    fprintf('正在保存 ICA 结果到 EEGLAB .set 文件: %s\n', output_set_file);
    [EEG, ~] = pop_saveset(EEG, 'filename', EEG.filename, 'filepath', EEG.filepath);
    
    fprintf('EEGLAB ICA 分析和保存完成。\n');
    fprintf('您现在可以在 EEGLAB GUI 中加载 %s 文件进行进一步检查和处理 (File -> Load existing dataset)。\n', output_set_file);
    fprintf('--------------------------------------------------\n');
end