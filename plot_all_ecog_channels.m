function plot_all_ecog_channels_single_plot()
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % MATLAB Script: plot_all_ecog_channels_single_plot.m
% %
% % 版权所有 (C) 2025 [Liuyangyang]
% % All rights reserved.
% %
% % 作者: [dalaoy]
% % 联系方式: [liuyangy2017@gmail.com]
% % 日期: 2025年7月12日 
% % 版本: 1.0 
% %
% % 描述: 读取 .mat 文件，并为指定范围内的所有 ECoG 通道在同一个图上生成时域图。
% %       默认只绘制数据的前 900 秒。
% %       
% %
% % 许可证: MIT License
% %
% % 依赖项: MATLAB R2017b 或更高版本。
% % %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



% plot_all_ecog_channels_single_plot
% 读取 .mat 文件，并为指定范围内的所有 ECoG 通道在同一个图上生成时域图。
% 默认绘制数据的前 900 秒。

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 指定通道时域图单图绘制工具\n');
    fprintf('--------------------------------------------------\n');

    % 1. 选择 .mat 文件
    [file, path] = uigetfile('*.mat', '选择预处理后的 ECoG 数据 .mat 文件 (包含 concatenated_ecog)');
    if file == 0
        fprintf('用户取消了文件选择。脚本结束。\n');
        return;
    end
    full_file_path = fullfile(path, file);
    
    fprintf('正在加载文件: %s...\n', full_file_path);
    try
        loaded_data = load(full_file_path);
    catch ME
        fprintf('加载文件失败: %s\n', ME.message);
        return;
    end
    fprintf('文件加载完成。\n');

    % 2. 提取数据和采样率
    if isfield(loaded_data, 'concatenated_ecog')
        ecog_data = loaded_data.concatenated_ecog;
        fprintf('找到 ECoG 数据变量: ''concatenated_ecog''.\n');
    elseif isfield(loaded_data, 'amplifier_data')
        ecog_data = loaded_data.amplifier_data;
        fprintf('找到 ECoG 数据变量: ''amplifier_data''.\n');
    else
        fprintf('错误: .mat 文件中未找到预期的 ECoG 数据变量 (''concatenated_ecog'' 或 ''amplifier_data'')。请检查文件内容。\n');
        return;
    end

    sampling_rate = [];
    if isfield(loaded_data, 'target_sampling_rate')
        sampling_rate = loaded_data.target_sampling_rate(1);
        fprintf('找到采样率变量: ''target_sampling_rate'': %g Hz.\n', sampling_rate);
    elseif isfield(loaded_data, 'frequency_parameters') && isfield(loaded_data.frequency_parameters, 'amplifier_sample_rate')
        sampling_rate = loaded_data.frequency_parameters.amplifier_sample_rate(1);
        fprintf('找到采样率变量: ''frequency_parameters.amplifier_sample_rate'': %g Hz.\n', sampling_rate);
    elseif isfield(loaded_data, 't_amplifier') && length(loaded_data.t_amplifier) > 1
        sampling_rate = 1 / mean(diff(loaded_data.t_amplifier));
        fprintf('从 ''t_amplifier'' 推断采样率: %g Hz.\n', sampling_rate);
    else
        fprintf('警告: 无法从文件中确定采样率。请手动输入或确保文件中包含采样率信息。\n');
        sampling_rate = input('请输入采样率 (Hz): ');
        if isempty(sampling_rate) || ~isscalar(sampling_rate) || sampling_rate <= 0
            fprintf('无效的采样率。脚本结束。\n');
            return;
        end
    end

    % 确保 ECoG 数据是 (通道数 x 采样点数) 格式
    if size(ecog_data, 1) > size(ecog_data, 2) && size(ecog_data, 2) <= 200 
        ecog_data = ecog_data'; 
        fprintf('数据已转置为 (通道数 x 采样点数) 格式。\n');
    end

    total_channels_available = size(ecog_data, 1);
    num_samples = size(ecog_data, 2);

    fprintf('检测到 %d 个可用通道，共 %d 个采样点。\n', total_channels_available, num_samples);
    fprintf('使用的采样率: %g Hz\n', sampling_rate);

    % 3. 定义绘制参数和选择通道范围
    channels_to_plot_start = 1; % 从通道 1 开始
    channels_to_plot_end = min(64, total_channels_available); % 绘制到通道 64，或到可用通道数的上限
    
    selected_channels = channels_to_plot_start:channels_to_plot_end;
    num_channels_to_display = length(selected_channels);

    plot_duration = 900; % 默认绘制前 900 秒的数据
    num_samples_to_plot = min(num_samples, round(plot_duration * sampling_rate));
    time_vector = (0:num_samples_to_plot-1) / sampling_rate;

    fprintf('将绘制通道 %d 到 %d 的数据，共 %d 个通道，显示前 %g 秒的数据。\n', ...
            channels_to_plot_start, channels_to_plot_end, num_channels_to_display, plot_duration);

    % 4. 绘制所有通道在同一个图上
    figure('Name', sprintf('ECoG 时域图 (%d-%d 通道)', channels_to_plot_start, channels_to_plot_end), ...
           'Units', 'normalized', 'OuterPosition', [0.1 0.1 0.8 0.8]); % 设置窗口大小

    hold on; % 允许在同一个轴上绘制多条线

    % 计算垂直偏移量
    % 找到所有选定通道的平均标准差或平均峰峰值，用于确定合适的偏移量
    % 使用 MAD (Median Absolute Deviation) 更鲁棒
    mad_vals = zeros(num_channels_to_display, 1);
    for i = 1:num_channels_to_display
        ch_data_segment = ecog_data(selected_channels(i), 1:num_samples_to_plot);
        if ~isempty(ch_data_segment)
            mad_vals(i) = median(abs(ch_data_segment - median(ch_data_segment)));
        end
    end
    avg_mad = mean(mad_vals);

    if avg_mad == 0
        % 如果所有通道都是常数信号，给一个默认偏移量
        vertical_offset_unit = 5; 
    else
        % 偏移量可以是平均信号波动范围的几倍 (例如 5 倍 MAD)
        vertical_offset_unit = avg_mad * 5; 
    end

    % 确保偏移量不是0，否则信号会重叠
    if vertical_offset_unit == 0
        vertical_offset_unit = 1; % 最小默认偏移
    end

    % 绘制每条线并添加偏移
    offset = 0;
    for i = 1:num_channels_to_display
        ch = selected_channels(i);
        plot_data = ecog_data(ch, 1:num_samples_to_plot) + offset;
        plot(time_vector, plot_data, 'DisplayName', sprintf('Ch %d', ch));
        
        % 增加偏移，为下一个通道做准备
        % 偏移量基于当前通道的幅值范围或固定值
        current_ch_amplitude = max(ecog_data(ch, 1:num_samples_to_plot)) - min(ecog_data(ch, 1:num_samples_to_plot));
        offset = offset + max(vertical_offset_unit, current_ch_amplitude * 0.8); % 偏移量取计算值和通道幅值范围的较大者
    end

    hold off; % 停止在同一轴上绘制

    % 设置图表标题和标签
    title_str = sprintf('ECoG 时域图 (通道 %d-%d) - %s (前 %g 秒)', ...
                        channels_to_plot_start, channels_to_plot_end, file, plot_duration);
    title(title_str);
    xlabel('时间 (秒)');
    ylabel('幅值 (带垂直偏移)');

    % 添加通道标签（Y轴刻度）
    channel_labels = cell(num_channels_to_display, 1);
    channel_ticks = zeros(num_channels_to_display, 1);
    
    current_offset_label = 0;
    for i = 1:num_channels_to_display
        ch = selected_channels(i);
        channel_labels{i} = sprintf('Ch %d', ch);
        % 这里需要根据绘制时的实际偏移来确定 Y 轴刻度位置
        % 由于偏移是累加的，可以近似计算每个通道的中线位置
        channel_ticks(i) = current_offset_label + (max(ecog_data(ch, 1:num_samples_to_plot)) + min(ecog_data(ch, 1:num_samples_to_plot))) / 2;
        
        current_ch_amplitude = max(ecog_data(ch, 1:num_samples_to_plot)) - min(ecog_data(ch, 1:num_samples_to_plot));
        current_offset_label = current_offset_label + max(vertical_offset_unit, current_ch_amplitude * 0.8);
    end

    set(gca, 'YTick', channel_ticks, 'YTickLabel', channel_labels, 'Box', 'on');
    grid on;

    fprintf('指定通道的时域图已在单图上生成。请查看弹出的图形窗口。\n');
    fprintf('--------------------------------------------------\n');

end