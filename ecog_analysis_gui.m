function ecog_analysis_script()
% ecog_analysis_script
%
% 这是一个基于传统 MATLAB GUI 框架的 ECoG 分析工具。
% 它提供了数据导入、平均参考、时域/频谱/时频可视化和功率热图功能，
% 并支持交互式静音离群通道。
% 新增功能：在分析前选择或排除部分通道。
% 新增功能：计算功率后保存到Excel表。
% 优化：时频图参数调整以提升频率分辨率（需GUI端手动调整TimeResField）。

    % 初始化 handles 结构体，用于存储所有 GUI 组件句柄和 App 状态数据
    handles = struct();

    % --- GUI 初始化和组件创建 ---
    createComponents();
    initializeChannelMap();
    updateHeatmapAxesLabels(); % 初始化热图轴标签

    % --- App 状态数据初始化 ---
    handles.ecog_data = [];         % 存储导入的原始 ECoG 数据（所有通道）
    handles.sampling_rate = [];     % 存储采样率
    handles.current_data = [];      % 当前处理的数据 (可能是原始或平均参考后的，且只包含活跃通道)
    handles.is_avg_ref = false;     % 标记是否已进行平均参考
    handles.muted_channels = [];    % 用于存储被静音的通道索引 (仅影响热图显示，通道必须是活跃的)
    handles.excluded_channels = []; % 用于存储被排除的通道索引 (影响平均参考和所有分析)
    handles.active_channels_overall = []; % 经过排除后的实际参与分析的原始通道索引
    handles.power_data_heatmap_calculated = containers.Map('KeyType', 'double', 'ValueType', 'double'); % 存储缓存的活跃通道原始ID -> 功率值
    handles.power_data_heatmap_calculated_freq_band = []; % 存储缓存功率对应的频段


    % --- 通道映射初始化 ---
    function initializeChannelMap()
        % 您提供的通道映射矩阵 (请确保这个矩阵包含了您所有需要映射的通道ID，例如通道11)
        % 如果您的电极编号就是1-based，并且是您实际的物理布局，请直接使用它。
        % 如果原始数据是0-based，并且这里是为了转换为1-based，则应该在加载原始map后加1。
        % 这里我直接使用您提供“加1后”的矩阵，这意味着GUI会按此矩阵来显示通道ID。
        channel_map_matrix_display = [
            12, 22, 38, 4;
            20, 48, 28, 27;
            10, 23, 57, 2;
            24, 49, 39, 29;
            14, 45, 59, 6;
            21, 51, 35, 31;
            16, 47, 64, 8;
            18, 54, 58, 25;
            17, 56, 41, 26;
            15, 50, 62, 7;
            43, 52, 37, 36;
            9, 40, 60, 1; 
            46, 53, 32, 34;
            11, 44, 61, 3; 
            42, 55, 30, 33;
            13, 19, 63, 5
        ];
        
        handles.max_row_map = size(channel_map_matrix_display, 1);
        handles.max_col_map = size(channel_map_matrix_display, 2);
        
        handles.channel_map_dict = containers.Map('KeyType', 'double', 'ValueType', 'any');
        for r = 1:handles.max_row_map
            for c = 1:handles.max_col_map
                channel_id = channel_map_matrix_display(r, c);
                % 确保channel_id是有效的1-64范围内的数字
                if channel_id >= 1 && channel_id <= 64 
                    handles.channel_map_dict(channel_id) = [r, c];
                end
            end
        end
    end

    % 更新热图轴标签，因为它是固定的
    function updateHeatmapAxesLabels()
        xlabel(handles.HeatmapAxes, '电极列');
        ylabel(handles.HeatmapAxes, '电极行');
        title(handles.HeatmapAxes, '通道功率热图');
    end

    % --- GUI 回调函数 ---

    % Button pushed function: SelectFileButton
    function SelectFileButtonPushed(src, event) 
        [file, path] = uigetfile('*.mat', '选择预处理的 .mat 文件');
        if file ~= 0
            full_path = fullfile(path, file);
            handles.FilePathLabel.Text = full_path;
            
            try
                loaded_data = load(full_path);
                if isfield(loaded_data, 'concatenated_ecog') && isfield(loaded_data, 'target_sampling_rate')
                    handles.ecog_data = loaded_data.concatenated_ecog;
                    handles.sampling_rate = loaded_data.target_sampling_rate;
                    
                    % 初始时，所有通道都是活跃的
                    all_ch = 1:size(handles.ecog_data, 1);
                    handles.active_channels_overall = all_ch; 
                    handles.current_data = handles.ecog_data; % 初始设置为原始数据
                    
                    handles.is_avg_ref = false; % 重置平均参考状态
                    handles.muted_channels = []; % 清空热图静音通道列表
                    handles.excluded_channels = []; % 清空排除通道列表
                    handles.power_data_heatmap_calculated = containers.Map('KeyType', 'double', 'ValueType', 'double'); % 清空已计算的热图数据
                    handles.power_data_heatmap_calculated_freq_band = []; % 清空缓存的频段

                    % 更新通道选择器的上限和显示
                    handles.ChannelSelectField.Limits(2) = size(handles.ecog_data, 1);
                    if handles.ChannelSelectField.Value > size(handles.ecog_data, 1)
                        handles.ChannelSelectField.Value = 1; % 默认选中第一个通道
                    end
                    handles.AllChannelsListLabel.Text = sprintf('可用通道: 1-%d', size(handles.ecog_data, 1));
                    handles.ExcludedChannelsField.Value = ''; % 清空排除通道输入框

                    uialert(handles.UIFigure, '数据导入成功！', '成功');
                    
                else
                    uialert(handles.UIFigure, '选择的 .mat 文件不包含 ''concatenated_ecog'' 或 ''target_sampling_rate'' 变量。', '错误');
                    handles.ecog_data = [];
                    handles.sampling_rate = [];
                    handles.active_channels_overall = [];
                    handles.current_data = [];
                end
            catch ME
                uialert(handles.UIFigure, ['加载文件失败: ', ME.message], '错误');
            end
        end
        guidata(src, handles); % 更新 handles 结构体
    end

    % Button pushed function: ApplyChannelExclusionButton
    function ApplyChannelExclusionButtonPushed(src, event)
        if isempty(handles.ecog_data)
            uialert(handles.UIFigure, '请先导入数据！', '警告');
            return;
        end 

        excluded_str = handles.ExcludedChannelsField.Value;
        
        try
            new_excluded_channels = str2num(excluded_str); %#ok<ST2NM>
            if isempty(new_excluded_channels) && ~isempty(excluded_str) 
                error('排除通道格式不正确，应为数字向量，例如 [1, 5, 10] 或 1:5。');
            end
            if ~isvector(new_excluded_channels) && ~isempty(new_excluded_channels) 
                 error('排除通道格式不正确，应为数字向量，例如 [1, 5, 10] 或 1:5。');
            end


            % 确保排除的通道号在有效范围内
            if any(new_excluded_channels < 1) || any(new_excluded_channels > size(handles.ecog_data, 1))
                error('排除通道号超出原始数据范围。');
            end
            
            handles.excluded_channels = unique(new_excluded_channels); % 存储排除通道并去重
            
            % 更新 active_channels_overall
            all_original_channels = 1:size(handles.ecog_data, 1);
            handles.active_channels_overall = setdiff(all_original_channels, handles.excluded_channels);
            
            % 更新 handles.current_data 为排除后的数据（用于后续分析）
            if isempty(handles.active_channels_overall)
                 handles.current_data = []; % 所有通道都被排除
                 uialert(handles.UIFigure, '所有通道都被排除，没有数据可供分析。', '警告');
            else
                 handles.current_data = handles.ecog_data(handles.active_channels_overall, :);
            end

            % 重置平均参考状态和缓存的功率数据，因为数据已经变化
            handles.is_avg_ref = false; 
            handles.power_data_heatmap_calculated = containers.Map('KeyType', 'double', 'ValueType', 'double'); % 清空缓存功率
            handles.power_data_heatmap_calculated_freq_band = []; % 清空缓存频段
            handles.muted_channels = []; % 排除通道也应该从静音中移除，重新开始静音

            % 更新可视化通道选择器的上限为活跃通道中的最大值
            if ~isempty(handles.active_channels_overall)
                % 可视化选择范围应该限制在活跃通道的原始ID范围内
                handles.ChannelSelectField.Limits = [min(handles.active_channels_overall) max(handles.active_channels_overall)];
                % 如果当前选择的通道被排除了，则重置为第一个活跃通道
                if ~ismember(handles.ChannelSelectField.Value, handles.active_channels_overall)
                    handles.ChannelSelectField.Value = handles.active_channels_overall(1);
                end
            else
                handles.ChannelSelectField.Limits = [1 1]; % 无活跃通道，限制为1
                handles.ChannelSelectField.Value = 1;
            end
            
            uialert(handles.UIFigure, sprintf('通道排除设置已应用。活跃通道: %d 个。', length(handles.active_channels_overall)), '成功');

        catch ME
            uialert(handles.UIFigure, ['应用通道排除设置失败: ', ME.message], '错误');
        end
        guidata(src, handles); % 更新 handles 结构体
    end


    % Button pushed function: AverageReferenceButton
    function AverageReferenceButtonPushed(src, event)
        if isempty(handles.current_data)
            uialert(handles.UIFigure, '请先导入数据或确保有活跃通道！', '警告');
            return;
        end 
        if handles.is_avg_ref
            uialert(handles.UIFigure, '数据已经应用过平均参考，请勿重复操作。', '警告');
            return;
        end 

        % 平均参考只基于 handles.current_data (即活跃通道)
        if size(handles.current_data, 1) < 2
            uialert(handles.UIFigure, '进行平均参考至少需要两个活跃通道。', '警告');
            return;
        end
        
        mean_data = mean(handles.current_data, 1);
        
        % 从每个活跃通道中减去平均值
        handles.current_data = handles.current_data - mean_data;
        handles.is_avg_ref = true;
        uialert(handles.UIFigure, '平均参考已成功应用。', '信息');
        guidata(src, handles); % 更新 handles 结构体
    end

    % Button pushed function: PlotTimeDomainButton
    function PlotTimeDomainButtonPushed(src, event)
        if isempty(handles.current_data)
            uialert(handles.UIFigure, '请先导入数据或确保有活跃通道！', 'WARNING'); 
            return;
        end 

        channel_original_id = handles.ChannelSelectField.Value; % GUI上选中的原始通道号
        
        % 检查用户选择的通道是否在活跃通道列表中
        [~, channel_idx_in_current_data] = ismember(channel_original_id, handles.active_channels_overall);
        
        if channel_idx_in_current_data == 0
            uialert(handles.UIFigure, sprintf('通道 %d 已被排除，无法可视化。请选择活跃通道。', channel_original_id), 'WARNING'); 
            return;
        end

        start_time = handles.StartTimeField.Value;
        duration = handles.DurationField.Value;
        sampling_rate = handles.sampling_rate;
        
        num_samples = size(handles.current_data, 2);
        
        % 计算起始和结束采样点
        start_sample = max(1, round(start_time * sampling_rate) + 1);
        end_sample = min(num_samples, round((start_time + duration) * sampling_rate));
        
        if start_sample >= end_sample
            uialert(handles.UIFigure, '时间范围无效或超出数据范围。', 'WARNING'); 
            return;
        end

        % 提取数据片段
        time_segment = handles.current_data(channel_idx_in_current_data, start_sample:end_sample);
        time_vector = (start_sample-1:end_sample-1) / sampling_rate;

        % 绘制
        cla(handles.TimeDomainAxes); % 清除当前轴
        plot(handles.TimeDomainAxes, time_vector, time_segment);
        title(handles.TimeDomainAxes, sprintf('时域波形 - 原始通道 %d', channel_original_id));
        xlabel(handles.TimeDomainAxes, '时间 (秒)');
        ylabel(handles.TimeDomainAxes, '幅值');
        grid(handles.TimeDomainAxes, 'on');
    end

    % Button pushed function: PlotSpectrumButton
    function PlotSpectrumButtonPushed(src, event)
        if isempty(handles.current_data)
            uialert(handles.UIFigure, '请先导入数据或确保有活跃通道！', 'WARNING'); 
            return;
        end 

        channel_original_id = handles.ChannelSelectField.Value;
        [~, channel_idx_in_current_data] = ismember(channel_original_id, handles.active_channels_overall);
        
        if channel_idx_in_current_data == 0
            uialert(handles.UIFigure, sprintf('通道 %d 已被排除，无法可视化。请选择活跃通道。', channel_original_id), 'WARNING'); 
            return;
        end
        sampling_rate = handles.sampling_rate;
        NFFT = handles.NFFTField.Value;
        
        % 确保数据长度足够进行 FFT
        if size(handles.current_data, 2) < NFFT
            uialert(handles.UIFigure, '数据长度不足以进行当前FFT点数计算。请选择较小的FFT点数或检查数据长度。', 'WARNING'); 
            return;
        end
        
        % 提取通道数据
        channel_data = handles.current_data(channel_idx_in_current_data, :);
        
        % 计算功率谱密度
        [Pxx, F] = pwelch(channel_data, NFFT, NFFT/2, NFFT, sampling_rate);
        
        % 绘制
        cla(handles.SpectrumAxes);
        plot(handles.SpectrumAxes, F, 10*log10(Pxx)); % 转换为dB
        title(handles.SpectrumAxes, sprintf('频谱图 - 原始通道 %d', channel_original_id));
        xlabel(handles.SpectrumAxes, '频率 (Hz)');
        ylabel(handles.SpectrumAxes, '功率/频率 (dB)');
        xlim(handles.SpectrumAxes, [0 sampling_rate/2]); % 显示到奈奎斯特频率
        grid(handles.SpectrumAxes, 'on');
    end

    % Button pushed function: PlotTimeFreqButton
    function PlotTimeFreqButtonPushed(src, event)
        if isempty(handles.current_data)
            uialert(handles.UIFigure, '请先导入数据或确保有活跃通道！', 'WARNING'); 
            return;
        end 

        channel_original_id = handles.ChannelSelectField.Value;
        [~, channel_idx_in_current_data] = ismember(channel_original_id, handles.active_channels_overall);
        
        if channel_idx_in_current_data == 0
            uialert(handles.UIFigure, sprintf('通道 %d 已被排除，无法可视化。请选择活跃通道。', channel_original_id), 'WARNING'); 
            return;
        end
        sampling_rate = handles.sampling_rate;
        freq_range_str = handles.FreqRangeField.Value;
        time_resolution = handles.TimeResField.Value;
        try
            freq_range = str2num(freq_range_str); %#ok<ST2NM>
            if ~isvector(freq_range) || length(freq_range) ~= 2 || freq_range(1) >= freq_range(2) || any(freq_range <= 0)
                error('频率范围格式不正确，应为 [min_freq max_freq]，且 min_freq < max_freq。');
            end
        catch
            uialert(handles.UIFigure, '时频图频率范围格式错误，请确保为 [min_freq max_freq] 格式。', 'ERROR'); 
            return;
        end
        channel_data = handles.current_data(channel_idx_in_current_data, :);
        
        % 使用短时傅里叶变换 (STFT) 进行时频分析
        window_len_samples = round(time_resolution * sampling_rate); 
        
        % 为了达到0.1Hz的频率分辨率，所需的窗长秒数至少是 1/0.1 = 10秒 (如果NFFT=窗长)
        % 所以，你需要将 time_resolution 设为至少 10。
        % 实际的频率分辨率会是 sampling_rate / window_len_samples
        
        % 例如，如果想频率分辨率大概 0.1 Hz
        desired_freq_res = 0.1; % Hz
        min_window_len_samples_for_freq_res = ceil(sampling_rate / desired_freq_res); 
        
        % 如果用户输入的 time_resolution 对应的 window_len_samples 太小，则提示
        if window_len_samples < min_window_len_samples_for_freq_res
            uialert(handles.UIFigure, sprintf('当前时间分辨率 (%g 秒) 对应的频率分辨率约为 %g Hz。\n为了达到 %.1f Hz 的频率分辨率，时间分辨率至少需要 %g 秒。', ...
                                              time_resolution, sampling_rate / window_len_samples, desired_freq_res, min_window_len_samples_for_freq_res / sampling_rate), ...
                                              '提示: 频率分辨率不足');
            % 强制将 window_len_samples 增大到满足频率分辨率要求
            window_len_samples = min_window_len_samples_for_freq_res;
            % 并且更新GUI上的时间分辨率字段，让用户知道实际使用了多大的窗长
            handles.TimeResField.Value = window_len_samples / sampling_rate;
        end
        
        % 确保 NFFT 至少等于窗长，并是2的幂次，以优化FFT性能
        NFFT_stft = 2^nextpow2(window_len_samples);
        
        noverlap = round(window_len_samples * 0.5); % 50% overlap
        if noverlap >= window_len_samples % 确保重叠小于窗长
             noverlap = window_len_samples - 1;
        end


        % 计算 STFT
        [S, F, T, P] = spectrogram(channel_data, window_len_samples, noverlap, NFFT_stft, sampling_rate);
        
        % 转换为 dB
        P_db = 10*log10(P + eps); % 加 eps 防止 log(0)

        % 裁剪频率范围
        freq_indices = F >= freq_range(1) & F <= freq_range(2);
        F_cropped = F(freq_indices);
        P_db_cropped = P_db(freq_indices, :);

        % 绘制
        cla(handles.TimeFreqAxes);
        imagesc(handles.TimeFreqAxes, T, F_cropped, P_db_cropped);
        axis(handles.TimeFreqAxes, 'xy'); % 反转Y轴使频率从低到高
        colorbar(handles.TimeFreqAxes, 'Location', 'eastoutside');
        colormap(handles.TimeFreqAxes, 'jet'); % 使用jet颜色图
        
        title(handles.TimeFreqAxes, sprintf('时频图 - 原始通道 %d (频率分辨率: %.2f Hz)', channel_original_id, sampling_rate / window_len_samples));
        xlabel(handles.TimeFreqAxes, '时间 (秒)');
        ylabel(handles.TimeFreqAxes, '频率 (Hz)');
    end

    % Button pushed function: CalculateHeatmapButton
    function CalculateHeatmapButtonPushed(src, event)
        if isempty(handles.current_data)
            uialert(handles.UIFigure, '请先导入数据或确保有活跃通道！', 'WARNING'); 
            return;
        end 
        freq_band_str = handles.PowerFreqBandField.Value;
        sampling_rate = handles.sampling_rate;
        
        try
            freq_band = str2num(freq_band_str); %#ok<ST2NM>
            if ~isvector(freq_band) || length(freq_band) ~= 2 || freq_band(1) >= freq_band(2) || any(freq_band <= 0)
                error('频段格式不正确，应为 [min_freq max_freq]，且 min_freq < max_freq。');
            end
        catch
            uialert(handles.UIFigure, '热图频段格式错误，请确保为 [min_freq max_freq] 格式。', 'ERROR'); 
            return;
        end

        num_active_channels = size(handles.current_data, 1);
        
        % 如果之前已经计算过功率，直接使用缓存，否则重新计算
        % 检查：1. 缓存是否为空 2. 频段是否改变 3. 活跃通道列表是否改变
        if handles.power_data_heatmap_calculated.Count == 0 || ... % Check if map is empty
           ~isequal(handles.power_data_heatmap_calculated_freq_band, freq_band) || ...
           ~isequal(sort(cell2mat(handles.power_data_heatmap_calculated.keys())), sort(handles.active_channels_overall)) 

            uialert(handles.UIFigure, '正在计算活跃通道功率，请稍候...', 'INFO'); drawnow; 
            
            NFFT = handles.NFFTField.Value; % 重用频谱图的FFT点数
            
            h_wait = uiprogressdlg(handles.UIFigure, 'Title', '计算功率中...', ...
                                   'Message', '请稍候...', 'Indeterminate', 'on');

            temp_power_map = containers.Map('KeyType', 'double', 'ValueType', 'double');
            for ch_idx = 1:num_active_channels % 遍历所有活跃通道计算功率
                original_ch_id = handles.active_channels_overall(ch_idx); % 获取原始通道ID
                channel_data = handles.current_data(ch_idx, :);
                
                [Pxx, F] = pwelch(channel_data, NFFT, NFFT/2, NFFT, sampling_rate);
                
                % 找到指定频段的索引
                freq_indices = F >= freq_band(1) & F <= freq_band(2);
                
                % 累加该频段的功率
                if any(freq_indices)
                    temp_power_map(original_ch_id) = sum(Pxx(freq_indices));
                else
                    temp_power_map(original_ch_id) = 0; % 如果频段内没有数据，功率为0
                end
            end
            close(h_wait);
            
            handles.power_data_heatmap_calculated = temp_power_map; % 缓存所有通道的功率
            handles.power_data_heatmap_calculated_freq_band = freq_band; % 缓存当前频段
            uialert(handles.UIFigure, '所有活跃通道功率计算完成。', 'SUCCESS'); 
        else
            uialert(handles.UIFigure, '使用缓存功率数据。', 'INFO'); drawnow; 
        end

        % 调用更新显示函数
        updateHeatmapDisplay(src, event);
        guidata(src, handles); % 更新 handles 结构体
    end

    % --- 保存功率数据到 Excel ---
    function SavePowerDataButtonPushed(src, event)
        if handles.power_data_heatmap_calculated.Count == 0 || isempty(handles.power_data_heatmap_calculated_freq_band)
            uialert(handles.UIFigure, '请先计算功率热图再保存！', 'WARNING'); 
            return;
        end 

        [file, path] = uiputfile({'*.xlsx','Excel Files (*.xlsx)'; '*.csv','CSV Files (*.csv)'}, '保存功率数据到文件');
        if file == 0
            return; % 用户取消
        end
        full_save_path = fullfile(path, file);

        % 获取缓存的功率数据和频段
        cached_power_map = handles.power_data_heatmap_calculated;
        freq_band = handles.power_data_heatmap_calculated_freq_band;

        % 1. 准备概要信息
        % 确保 all_powers 不为空，否则 max/min/mean 会报错
        if cached_power_map.Count > 0
            all_powers_val = cell2mat(cached_power_map.values());
            max_power = max(all_powers_val);
            min_power = min(all_powers_val);
            mean_power = mean(all_powers_val);
        else
            max_power = NaN;
            min_power = NaN;
            mean_power = NaN;
        end

        summary_data = {
            '功率范围', sprintf('[%g - %g] Hz', freq_band(1), freq_band(2));
            '包含的活跃通道数', length(handles.active_channels_overall);
            '最高功率', max_power;
            '最低功率', min_power;
            '平均功率', mean_power;
            '排除通道 (原始ID)', mat2str(handles.excluded_channels);
            '静音通道 (仅热图显示, 原始ID)', mat2str(handles.muted_channels);
        };
        
        % 2. 准备详细功率列表
        % 遍历所有可能的原始通道ID (根据ecog_data的尺寸)
        all_original_channel_ids_sorted = sort(1:size(handles.ecog_data, 1)); 
        detail_data_header = {'通道号 (原始ID)', '功率值', '备注'};
        detail_data_rows = cell(length(all_original_channel_ids_sorted), 3);

        for i = 1:length(all_original_channel_ids_sorted)
            ch_id = all_original_channel_ids_sorted(i);
            detail_data_rows{i, 1} = ch_id;
            
            if ismember(ch_id, handles.excluded_channels)
                detail_data_rows{i, 2} = 'N/A';
                detail_data_rows{i, 3} = '通道已排除 (未参与分析)';
            elseif ~isKey(handles.channel_map_dict, ch_id)
                % 检查该通道是否在映射中
                detail_data_rows{i, 2} = 'N/A';
                detail_data_rows{i, 3} = '通道未在映射中';
            elseif isKey(cached_power_map, ch_id) % 如果它是活跃通道且有功率值
                detail_data_rows{i, 2} = cached_power_map(ch_id);
                detail_data_rows{i, 3} = '活跃通道';
                if ismember(ch_id, handles.muted_channels)
                     detail_data_rows{i, 3} = [detail_data_rows{i, 3}, ' (热图已静音)'];
                end
            else 
                % 如果一个通道既没被排除，又在映射中，但又不在缓存功率Map里
                % 这意味着它可能是一个有效通道，但在功率计算时其值很小或为0
                % 或者它在映射中，但实际数据根本就没有这个通道
                detail_data_rows{i, 2} = 0; % 假设为0功率
                detail_data_rows{i, 3} = '活跃通道 (功率为0)';
                if ismember(ch_id, handles.muted_channels)
                     detail_data_rows{i, 3} = [detail_data_rows{i, 3}, ' (热图已静音)'];
                end
            end
        end
        
        full_detail_table = [detail_data_header; detail_data_rows];

        try
            % 写入 Excel
            if contains(lower(file), '.xlsx')
                writetable(cell2table(summary_data), full_save_path, 'Sheet', '功率概要', 'WriteVariableNames', false);
                writetable(cell2table(full_detail_table), full_save_path, 'Sheet', '详细功率列表', 'WriteVariableNames', false);
            elseif contains(lower(file), '.csv')
                % CSV 不支持多表，简单地将概要和详情写在一起
                warning('CSV 格式不支持多工作表，将概要和详细数据写入同一文件。');
                fid = fopen(full_save_path, 'wt');
                if fid == -1, error('无法打开文件进行写入。'); end
                
                fprintf(fid, '功率概要\n');
                for r_sum = 1:size(summary_data,1)
                    fprintf(fid, '%s,%s\n', summary_data{r_sum,1}, string(summary_data{r_sum,2})); % Convert second column to string
                end
                fprintf(fid, '\n'); % 空行分隔
                
                for r_det = 1:size(full_detail_table,1)
                    fprintf(fid, '%s,%s,%s\n', string(full_detail_table{r_det,1}), string(full_detail_table{r_det,2}), string(full_detail_table{r_det,3}));
                end
                fclose(fid);
            end
            uialert(handles.UIFigure, sprintf('功率数据已成功保存到:\n%s', full_save_path), 'SUCCESS'); 
        catch ME
            uialert(handles.UIFigure, ['保存文件失败: ', ME.message], 'ERROR'); 
        end
        guidata(src, handles);
    end

    % --- 热图点击静音功能 ---
    function muteChannelClick(src, event) 
        if handles.power_data_heatmap_calculated.Count == 0 
            uialert(handles.UIFigure, '请先计算功率热图再进行静音操作！', 'WARNING'); 
            return;
        end % Corrected curly brace to parenthesis

        % 获取点击的坐标
        click_point = get(src, 'CurrentPoint');
        clicked_col = round(click_point(1,1));
        clicked_row = round(click_point(1,2));

        % 检查点击是否在有效范围内
        if clicked_row >= 1 && clicked_row <= handles.max_row_map && ...
           clicked_col >= 1 && clicked_col <= handles.max_col_map
            
            % 查找被点击的原始通道号
            clicked_original_channel_id = -1;
            all_ch_ids_cell = keys(handles.channel_map_dict); 

            for k_idx = 1:length(all_ch_ids_cell)
                ch_id = all_ch_ids_cell{k_idx}; 
                coords = handles.channel_map_dict(ch_id);
                if coords(1) == clicked_row && coords(2) == clicked_col
                    clicked_original_channel_id = ch_id;
                    break;
                end
            end

            if clicked_original_channel_id ~= -1
                % 检查该通道是否是活跃通道（即未被排除的通道）
                if ismember(clicked_original_channel_id, handles.excluded_channels)
                    uialert(handles.UIFigure, sprintf('通道 %d 已被排除，无法静音/取消静音。', clicked_original_channel_id), 'WARNING'); 
                    return;
                end
                
                % 检查该通道是否在映射中 (理论上这里已经通过map_dict查到了)
                if ~isKey(handles.channel_map_dict, clicked_original_channel_id)
                     uialert(handles.UIFigure, sprintf('通道 %d 未在映射中，无法静音/取消静音。', clicked_original_channel_id), 'WARNING'); 
                     return;
                end

                % 切换静音状态
                if ismember(clicked_original_channel_id, handles.muted_channels)
                    % 取消静音
                    handles.muted_channels = setdiff(handles.muted_channels, clicked_original_channel_id);
                    uialert(handles.UIFigure, sprintf('通道 %d 已取消静音。', clicked_original_channel_id), 'INFO'); 
                else
                    % 静音
                    handles.muted_channels = [handles.muted_channels, clicked_original_channel_id];
                    uialert(handles.UIFigure, sprintf('通道 %d 已静音。', clicked_original_channel_id), 'INFO'); 
                end
                
                guidata(src, handles); % 更新 handles 结构体
                updateHeatmapDisplay(src, event); % 触发热图更新
            else
                fprintf('点击位置 (%d, %d) 处没有找到对应通道。\n', clicked_row, clicked_col);
            end
        else
            fprintf('点击位置 (%d, %d) 超出热图范围。\n', clicked_row, clicked_col);
        end
    end

    % --- 仅更新热图显示，不重新计算功率 ---
    function updateHeatmapDisplay(src, event)
        if handles.power_data_heatmap_calculated.Count == 0 || isempty(handles.power_data_heatmap_calculated_freq_band)
            uialert(handles.UIFigure, '请先计算功率热图！', 'WARNING'); 
            return;
        end % Corrected curly brace to parenthesis
        
        % 总的原始通道数，用于在热图上显示所有可能的通道号
        num_total_original_channels = size(handles.ecog_data, 1); 
        cached_power_map = handles.power_data_heatmap_calculated; % Map (原始通道ID -> 功率)
        freq_band = handles.power_data_heatmap_calculated_freq_band; % 使用缓存的频段信息

        % 将功率值映射到电极布局矩阵，并应用静音/排除
        display_heatmap_matrix = zeros(handles.max_row_map, handles.max_col_map);
        all_map_ch_ids_cell = keys(handles.channel_map_dict); % 映射中存在的通道ID

        for r = 1:handles.max_row_map
            for c = 1:handles.max_col_map
                current_original_ch_id = -1;
                for i = 1:length(all_map_ch_ids_cell)
                    ch_key = all_map_ch_ids_cell{i};
                    coords = handles.channel_map_dict(ch_key);
                    if coords(1) == r && coords(2) == c
                        current_original_ch_id = ch_key;
                        break;
                    end
                end

                if current_original_ch_id ~= -1 % 这是一个在映射中的有效通道
                    if ismember(current_original_ch_id, handles.excluded_channels) % 被排除的通道
                        display_heatmap_matrix(r, c) = NaN; % 显示为空白
                    elseif ismember(current_original_ch_id, handles.muted_channels) % 被静音的通道
                         display_heatmap_matrix(r, c) = NaN; % 显示为空白
                    elseif isKey(cached_power_map, current_original_ch_id) % 如果在缓存的功率Map中
                         display_heatmap_matrix(r, c) = cached_power_map(current_original_ch_id); % 显示实际功率
                    else 
                         % 这种情况：通道在映射中，但不在活跃通道列表（因其未参与计算），或者功率为0
                         % 此时将其显示为0，让文本颜色来区分
                         display_heatmap_matrix(r, c) = 0; 
                    end
                else
                    display_heatmap_matrix(r, c) = NaN; % 对于映射中不存在的空白位置也显示为NaN
                end
            end
        end
        
        % 绘制热图
        cla(handles.HeatmapAxes);
        h_heatmap = imagesc(handles.HeatmapAxes, display_heatmap_matrix);
        
        % 设置颜色条和标题
        cbar = colorbar(handles.HeatmapAxes, 'Location', 'eastoutside');
        title(cbar, '功率');
        colormap(handles.HeatmapAxes, 'jet');
        % 动态调整颜色限制，排除 NaN 和 0
        valid_powers_for_caxis = display_heatmap_matrix(~isnan(display_heatmap_matrix) & display_heatmap_matrix ~= 0);
        if ~isempty(valid_powers_for_caxis)
            caxis(handles.HeatmapAxes, [min(valid_powers_for_caxis), max(valid_powers_for_caxis)]);
        else
            caxis(handles.HeatmapAxes, [0, 1]); % 默认值或空图
        end
        
        title(handles.HeatmapAxes, sprintf('通道功率热图 (%g-%g Hz)', freq_band(1), freq_band(2)));
        
        set(handles.HeatmapAxes, 'XTick', 1:handles.max_col_map, 'YTick', 1:handles.max_row_map);
        axis(handles.HeatmapAxes, 'ij'); 
        
        % 在每个电极位置显示通道号
        % 遍历所有原始通道，确保所有通道号都显示，并根据状态着色
        for ch_id = 1:num_total_original_channels 
            if isKey(handles.channel_map_dict, ch_id)
                coords = handles.channel_map_dict(ch_id);
                row = coords(1);
                col = coords(2);
                
                txt_color = 'white'; % 默认颜色
                if ismember(ch_id, handles.excluded_channels)
                    txt_color = [0.5 0.5 0.5]; % 排除通道显示灰色
                elseif ismember(ch_id, handles.muted_channels)
                    txt_color = 'red'; % 静音通道显示红色
                elseif ~ismember(ch_id, handles.active_channels_overall) % 如果不在活跃通道列表（已被排除），显示灰色
                    txt_color = [0.5 0.5 0.5]; 
                end
                
                text(handles.HeatmapAxes, col, row, num2str(ch_id), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'Color', txt_color, 'FontSize', 8, 'HitTest', 'off'); 
            end
        end
        guidata(src, handles); % 更新 handles 结构体
    end


    % --- 组件创建函数 ---
    function createComponents()
        % Create UIFigure and components
        handles.UIFigure = uifigure('Visible', 'off');
        handles.UIFigure.Position = [100 100 1200 800];
        handles.UIFigure.Name = 'ECoG 分析工具';
        handles.UIFigure.AutoResizeChildren = 'off'; % Custom resizing

        % Create a main grid layout
        mainGrid = uigridlayout(handles.UIFigure, [1 2]);
        mainGrid.RowHeight = {'1x'};
        mainGrid.ColumnWidth = {'1x', '2x'};

        % Create LeftPanel (control panel)
        handles.LeftPanel = uipanel(mainGrid);
        handles.LeftPanel.TitlePosition = 'centertop';
        handles.LeftPanel.Title = '控制面板';
        handles.LeftPanel.Layout.Row = 1;
        handles.LeftPanel.Layout.Column = 1;
        
        % Grid layout for LeftPanel
        leftGrid = uigridlayout(handles.LeftPanel, [7 1]); % 增加一行用于保存按钮
        leftGrid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}; % All 'fit' for dynamic sizing
        leftGrid.ColumnWidth = {'1x'};
        leftGrid.Padding = [5 5 5 5];

        % File Selection Panel
        handles.FileSelectionPanel = uipanel(leftGrid);
        handles.FileSelectionPanel.Title = '数据导入';
        handles.FileSelectionPanel.Layout.Row = 1;
        fileGrid = uigridlayout(handles.FileSelectionPanel, [3 1]);
        fileGrid.RowHeight = {20, 20, 30};
        handles.FilePathLabel = uilabel(fileGrid);
        handles.FilePathLabel.Text = '未选择文件';
        handles.SelectFileButton = uibutton(fileGrid, 'push');
        handles.SelectFileButton.ButtonPushedFcn = @(src, event) SelectFileButtonPushed(src, event);
        handles.SelectFileButton.Text = '选择 .mat 文件';

        % Channel Exclusion Panel (New)
        handles.ChannelExclusionPanel = uipanel(leftGrid);
        handles.ChannelExclusionPanel.Title = '通道选择/排除';
        handles.ChannelExclusionPanel.Layout.Row = 2; % 第二行
        exclusionGrid = uigridlayout(handles.ChannelExclusionPanel, [4 1]);
        exclusionGrid.RowHeight = {20, 20, 30, 30};
        
        handles.AllChannelsListLabel = uilabel(exclusionGrid);
        handles.AllChannelsListLabel.Text = '可用通道: 无数据'; % 初始显示
        
        uilabel(exclusionGrid, 'Text', '排除通道号 (例: [1, 5, 10]):');
        handles.ExcludedChannelsField = uieditfield(exclusionGrid, 'text');
        handles.ExcludedChannelsField.Value = '';
        
        handles.ApplyChannelExclusionButton = uibutton(exclusionGrid, 'push');
        handles.ApplyChannelExclusionButton.ButtonPushedFcn = @(src, event) ApplyChannelExclusionButtonPushed(src, event);
        handles.ApplyChannelExclusionButton.Text = '应用排除通道设置';

        % Analysis Controls (Average Reference)
        handles.AnalysisControlsPanel = uipanel(leftGrid);
        handles.AnalysisControlsPanel.Title = '全局操作';
        handles.AnalysisControlsPanel.Layout.Row = 3; % 变为第三行
        analysisGrid = uigridlayout(handles.AnalysisControlsPanel, [1 1]);
        analysisGrid.RowHeight = {'1x'};
        analysisGrid.ColumnWidth = {'1x'};
        handles.AverageReferenceButton = uibutton(analysisGrid, 'push');
        handles.AverageReferenceButton.ButtonPushedFcn = @(src, event) AverageReferenceButtonPushed(src, event);
        handles.AverageReferenceButton.Text = '执行平均参考';

        % Visualization Panel
        handles.VisualizationPanel = uipanel(leftGrid);
        handles.VisualizationPanel.Title = '可视化设置';
        handles.VisualizationPanel.Layout.Row = 4; % 变为第四行
        visGrid = uigridlayout(handles.VisualizationPanel, [5 1]); 
        visGrid.RowHeight = {20, 30, 'fit', 'fit', 'fit'}; 
        visGrid.ColumnWidth = {'1x'};

        handles.ChannelSelectLabel = uilabel(visGrid);
        handles.ChannelSelectLabel.Text = '选择可视化通道 (原始ID):'; % 明确提示是原始ID
        handles.ChannelSelectField = uieditfield(visGrid, 'numeric');
        handles.ChannelSelectField.Value = 1;
        handles.ChannelSelectField.Limits = [1 128]; % 初始范围仍是1-128，导入数据后会更新上限
        handles.ChannelSelectField.RoundFractionalValues = 'on';

        % Time Domain Settings
        handles.TimeDomainSettingsPanel = uipanel(visGrid);
        handles.TimeDomainSettingsPanel.Title = '时域图';
        timeDomainGrid = uigridlayout(handles.TimeDomainSettingsPanel, [3 2]);
        timeDomainGrid.RowHeight = {20, 20, 30};
        timeDomainGrid.ColumnWidth = {'1x', '1x'};
        handles.StartTimeLabel = uilabel(timeDomainGrid);
        handles.StartTimeLabel.Text = '起始时间 (秒):';
        handles.StartTimeField = uieditfield(timeDomainGrid, 'numeric');
        handles.StartTimeField.Value = 0;
        handles.DurationLabel = uilabel(timeDomainGrid);
        handles.DurationLabel.Text = '持续时间 (秒):';
        handles.DurationField = uieditfield(timeDomainGrid, 'numeric');
        handles.DurationField.Value = 300;
        handles.PlotTimeDomainButton = uibutton(timeDomainGrid, 'push');
        handles.PlotTimeDomainButton.ButtonPushedFcn = @(src, event) PlotTimeDomainButtonPushed(src, event);
        handles.PlotTimeDomainButton.Text = '显示时域图';
        handles.PlotTimeDomainButton.Layout.Column = [1 2];

        % Spectrum Settings
        handles.SpectrumSettingsPanel = uipanel(visGrid);
        handles.SpectrumSettingsPanel.Title = '频谱图';
        spectrumGrid = uigridlayout(handles.SpectrumSettingsPanel, [2 2]);
        spectrumGrid.RowHeight = {20, 30};
        spectrumGrid.ColumnWidth = {'1x', '1x'};
        handles.NFFTLabel = uilabel(spectrumGrid);
        handles.NFFTLabel.Text = 'FFT点数:';
        handles.NFFTField = uieditfield(spectrumGrid, 'numeric');
        handles.NFFTField.Value = 2048;
        handles.NFFTField.Limits = [128 inf];
        handles.PlotSpectrumButton = uibutton(spectrumGrid, 'push');
        handles.PlotSpectrumButton.ButtonPushedFcn = @(src, event) PlotSpectrumButtonPushed(src, event);
        handles.PlotSpectrumButton.Text = '显示频谱图';
        handles.PlotSpectrumButton.Layout.Column = [1 2];

        % Time-Frequency Settings
        handles.TimeFreqSettingsPanel = uipanel(leftGrid);
        handles.TimeFreqSettingsPanel.Title = '时频图';
        handles.TimeFreqSettingsPanel.Layout.Row = 5; % 变为第五行
        timeFreqGrid = uigridlayout(handles.TimeFreqSettingsPanel, [3 2]);
        timeFreqGrid.RowHeight = {20, 20, 30};
        timeFreqGrid.ColumnWidth = {'1x', '1x'};
        handles.FreqRangeLabel = uilabel(timeFreqGrid);
        handles.FreqRangeLabel.Text = '频率范围 (Hz, [min max]):';
        handles.FreqRangeField = uieditfield(timeFreqGrid, 'text');
        handles.FreqRangeField.Value = '[1 200]';
        handles.TimeResLabel = uilabel(timeFreqGrid);
        handles.TimeResLabel.Text = '时间分辨率 (秒):';
        handles.TimeResField = uieditfield(timeFreqGrid, 'numeric');
        handles.TimeResField.Value = 0.1;
        handles.PlotTimeFreqButton = uibutton(timeFreqGrid, 'push');
        handles.PlotTimeFreqButton.ButtonPushedFcn = @(src, event) PlotTimeFreqButtonPushed(src, event);
        handles.PlotTimeFreqButton.Text = '显示时频图';
        handles.PlotTimeFreqButton.Layout.Column = [1 2];

        % Power Heatmap Panel
        handles.PowerHeatmapPanel = uipanel(leftGrid);
        handles.PowerHeatmapPanel.Title = '功率热图';
        handles.PowerHeatmapPanel.Layout.Row = 6; % 变为第六行
        heatmapGrid = uigridlayout(handles.PowerHeatmapPanel, [3 2]);
        heatmapGrid.RowHeight = {20, 20, 30};
        heatmapGrid.ColumnWidth = {'1x', '1x'};
        handles.PowerFreqBandLabel = uilabel(heatmapGrid);
        handles.PowerFreqBandLabel.Text = '热图频段 (Hz, [min max]):';
        handles.PowerFreqBandField = uieditfield(heatmapGrid, 'text');
        handles.PowerFreqBandField.Value = '[80 150]'; % Default band
        handles.CalculateHeatmapButton = uibutton(heatmapGrid, 'push');
        handles.CalculateHeatmapButton.ButtonPushedFcn = @(src, event) CalculateHeatmapButtonPushed(src, event);
        handles.CalculateHeatmapButton.Text = '计算并显示热图';
        handles.CalculateHeatmapButton.Layout.Column = [1 2];

        % Save Power Data Button (New)
        handles.SavePowerDataButton = uibutton(leftGrid, 'push');
        handles.SavePowerDataButton.Text = '保存功率数据到Excel';
        handles.SavePowerDataButton.Layout.Row = 7; % 变为第七行
        handles.SavePowerDataButton.Layout.Column = 1;
        handles.SavePowerDataButton.ButtonPushedFcn = @(src, event) SavePowerDataButtonPushed(src, event);


        % RightPanel (display area)
        handles.RightPanel = uipanel(mainGrid);
        handles.RightPanel.TitlePosition = 'centertop';
        handles.RightPanel.Title = '可视化结果';
        handles.RightPanel.Layout.Row = 1;
        handles.RightPanel.Layout.Column = 2;

        % Grid layout for RightPanel axes
        rightGrid = uigridlayout(handles.RightPanel, [2 2]);
        rightGrid.RowHeight = {'1x', '1x'};
        rightGrid.ColumnWidth = {'1x', '1x'};

        % Axes for plots
        handles.TimeDomainAxes = uiaxes(rightGrid);
        handles.TimeDomainAxes.Layout.Row = 1;
        handles.TimeDomainAxes.Layout.Column = 1;
        title(handles.TimeDomainAxes, '时域波形');
        xlabel(handles.TimeDomainAxes, '时间 (秒)');
        ylabel(handles.TimeDomainAxes, '幅值');
        grid(handles.TimeDomainAxes, 'on');

        handles.SpectrumAxes = uiaxes(rightGrid);
        handles.SpectrumAxes.Layout.Row = 1;
        handles.SpectrumAxes.Layout.Column = 2;
        title(handles.SpectrumAxes, '频谱图');
        xlabel(handles.SpectrumAxes, '频率 (Hz)');
        ylabel(handles.SpectrumAxes, '功率/频率 (dB)');
        grid(handles.SpectrumAxes, 'on');

        handles.TimeFreqAxes = uiaxes(rightGrid);
        handles.TimeFreqAxes.Layout.Row = 2;
        handles.TimeFreqAxes.Layout.Column = 1;
        title(handles.TimeFreqAxes, '时频图');
        xlabel(handles.TimeFreqAxes, '时间 (秒)');
        ylabel(handles.TimeFreqAxes, '频率 (Hz)');

        handles.HeatmapAxes = uiaxes(rightGrid);
        handles.HeatmapAxes.Layout.Row = 2;
        handles.HeatmapAxes.Layout.Column = 2;
        handles.HeatmapAxes.ButtonDownFcn = @(src, event) muteChannelClick(src, event);

        % Show the figure after all components are created
        handles.UIFigure.Visible = 'on';
    end

end