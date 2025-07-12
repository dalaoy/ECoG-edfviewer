function inspect_ica_components(input_mat_file, num_components_to_inspect, max_freq_for_spectrum)
% inspect_ica_components: 运行ICA并可视化每个独立成分的时间序列和频谱。
%   用于人工识别潜在的伪迹成分，以帮助调整自动去除的阈值。
%
%   input_mat_file:             预处理后的 .mat 文件路径。
%   num_components_to_inspect:  要可视化的独立成分数量 (通常是通道数)。
%   max_freq_for_spectrum:      频谱图的最大频率显示范围 (Hz)。

    if nargin < 3
        error('请提供输入 .mat 文件路径、要查看的成分数量和频谱最大频率。');
    end

    fprintf('--------------------------------------------------\n');
    fprintf('ICA 独立成分诊断工具开始\n');
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
    if size(ecog_data_raw, 1) > size(ecog_data_raw, 2) && size(ecog_data_raw, 2) < 200 
        ecog_data_raw = ecog_data_raw'; 
        fprintf('数据已转置为 (通道数 x 采样点数)。\n');
    end
    
    nbchan = size(ecog_data_raw, 1);
    pnts = size(ecog_data_raw, 2);

    if num_components_to_inspect > nbchan
        warning('要查看的成分数量 (%d) 超过了通道数 (%d)，将只查看所有通道数。', num_components_to_inspect, nbchan);
        num_components_to_inspect = nbchan;
    end

    % 2. 数据预处理 for ICA (零均值)
    fprintf('正在对数据进行零均值处理...\n');
    ecog_data_demeaned = bsxfun(@minus, ecog_data_raw, mean(ecog_data_raw, 2));

    % 3. 运行 ICA
    fprintf('正在运行 ICA (使用 rica 函数)...\n');
    try
        Mdl = rica(ecog_data_demeaned', num_components_to_inspect); % Data' (timepoints x nbchan)
        ica_components_time_by_ic = Mdl.transform(ecog_data_demeaned'); % ICs (timepoints x num_components)
        ica_components = ica_components_time_by_ic'; % Transpose to (num_components x timepoints)
        ica_weights = Mdl.TransformWeights; % W*K matrix (num_components x nbchan)
        ica_inv_weights = inv(ica_weights); % inv(W*K) matrix (nbchan x num_components)

        fprintf('ICA 分析完成 (使用 rica)。\n');
    catch ME
        if (strcmp(ME.identifier, 'MATLAB:UndefinedFunction'))
            error('未找到 rica 函数。请确保已安装 Statistics and Machine Learning Toolbox。');
        else
            rethrow(ME);
        end
    end

    % 4. 可视化每个独立成分
    fprintf('正在生成独立成分的可视化图窗...\n');
    
    % 每个成分绘制一个子图，包含时间序列和频谱
    % 布局：每行 2 个子图 (时域，频谱)
    
    % 为了控制图窗数量，每个图窗显示一定数量的成分
    components_per_figure = 10; % 每个图窗显示 10 个成分
    num_figures = ceil(num_components_to_inspect / components_per_figure);

    for fig_idx = 1:num_figures
        figure('Name', sprintf('ICA 成分诊断 - 图 %d/%d', fig_idx, num_figures), ...
               'Units', 'normalized', 'OuterPosition', [0.05 0.05 0.9 0.9]); % 设置窗口大小
        
        start_ic = (fig_idx - 1) * components_per_figure + 1;
        end_ic = min(num_components_to_inspect, fig_idx * components_per_figure);
        
        current_subplot_row = 0;
        for ic = start_ic:end_ic
            current_subplot_row = current_subplot_row + 1;
            
            ic_data = ica_components(ic, :);
            
            % --- 绘制时间序列 ---
            subplot(components_per_figure, 2, (current_subplot_row-1)*2 + 1);
            plot_duration = min(20, pnts/srate); % 绘制前20秒或全部数据
            plot_samples = round(plot_duration * srate);
            time_vector = (0:plot_samples-1) / srate;

            plot(time_vector, ic_data(1:plot_samples));
            title(sprintf('IC %d 时域 (前 %g s)', ic, plot_duration), 'FontSize', 8);
            ylabel('幅值', 'FontSize', 7);
            set(gca, 'XTickLabel', '', 'YTickLabel', '', 'Box', 'off'); % 隐藏刻度
            xlim([0 plot_duration]);
            
            % --- 绘制频谱 ---
            subplot(components_per_figure, 2, (current_subplot_row-1)*2 + 2);
            % 使用 pwelch 计算功率谱密度
            NFFT_spectrum = srate; % 1秒窗长，频率分辨率1Hz
            [Pxx, F] = pwelch(ic_data, NFFT_spectrum, NFFT_spectrum/2, NFFT_spectrum, srate);
            
            plot(F, 10*log10(Pxx)); % 转换为dB
            title(sprintf('IC %d 频谱', ic), 'FontSize', 8);
            xlabel('频率 (Hz)', 'FontSize', 7);
            ylabel('功率 (dB)', 'FontSize', 7);
            xlim([0 max_freq_for_spectrum]); % 显示指定频率范围
            grid on;
            set(gca, 'YTickLabel', '', 'Box', 'off'); % 隐藏Y刻度

            % 突出显示高频肌电频段 (可选)
            % area(F(F>=30 & F<=100), 10*log10(Pxx(F>=30 & F<=100)), min(10*log10(Pxx)), 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none', 'DisplayName', 'EMG Band');
            % legend('off');
        end
        sgtitle(sprintf('独立成分时域与频谱 (数据: %s)', input_mat_file), 'Interpreter', 'none');
    end

    fprintf('\n独立成分可视化图窗已生成。请仔细检查每个成分:\n');
    fprintf('  - 寻找高频（特别是 >30Hz）能量显著的成分。\n');
    fprintf('  - 寻找时间序列中表现为尖锐、爆发性（高幅值、窄持续时间）的成分。\n');
    fprintf('  - 记录您认为是伪迹的成分ID (例如: 3, 7, 15)。\n');
    fprintf('  - 根据观察调整 clean_ecog_ica_matlab.m 脚本中的 ''kurtosis_threshold'' 和 ''power_ratio_threshold''。\n');
    fprintf('--------------------------------------------------\n');

end