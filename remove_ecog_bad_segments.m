function output_file_path = remove_ecog_bad_segments(input_mat_file, output_prefix)
% remove_ecog_bad_segments: 手动标记并去除ECoG信号中的坏段，并进行插值平滑处理。
%
%   这个函数会读取您预处理后的ECoG数据，允许您通过命令行输入肌电伪迹等坏段的
%   起始和结束时间（以秒为单位）。它会将这些坏段的数据置为NaN，然后进行插值
%   平滑连接，最后将清理后的信号保存为一个新的.mat文件。
%
%   输入参数:
%     input_mat_file:   输入.mat文件的完整路径。该文件应包含：
%                       - 'concatenated_ecog' 变量（ECoG数据，通道数 x 采样点数）
%                       - 'target_sampling_rate' 变量（采样率）
%     output_prefix:    输出干净信号.mat文件的前缀名 (例如 'ecog_cleaned_emg')。
%                       输出文件将保存在输入文件所在的文件夹中。
%
%   输出:
%     output_file_path: 成功保存的干净信号文件的完整路径。
%
%   示例用法:
%     % 假设您的预处理文件是： D:\MyData\Session1\rat_ecog_preprocessed.mat
%     input_data_file = 'D:\MyData\Session1\rat_ecog_preprocessed.mat';
%     output_base_name = 'rat_ecog_emg_cleaned';
%
%     % 调用函数执行清理
%     cleaned_data_file = remove_ecog_bad_segments(input_data_file, output_base_name);
%     fprintf('清理后的数据已保存到: %s\n', cleaned_data_file);

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 坏段去除与插值脚本启动\n');
    fprintf('--------------------------------------------------\n');

    % --- 1. 加载您的ECoG数据 ---
    fprintf('正在加载数据文件: %s...\n', input_mat_file);
    try
        loaded_data = load(input_mat_file);
    catch ME
        error('加载输入 .mat 文件失败: %s', ME.message);
    end

    % 检查并提取ECoG数据和采样率
    if isfield(loaded_data, 'concatenated_ecog')
        ecog_data = loaded_data.concatenated_ecog;
        fprintf('  ECoG数据成功加载，形状为: %s\n', mat2str(size(ecog_data)));
    else
        error('错误: 输入 .mat 文件中未找到 ''concatenated_ecog'' 变量。请确保文件名和内容正确。');
    end

    if isfield(loaded_data, 'target_sampling_rate')
        srate = loaded_data.target_sampling_rate(1); % 确保是标量
        fprintf('  采样率成功加载: %g Hz\n', srate);
    else
        error('错误: 输入 .mat 文件中未找到 ''target_sampling_rate'' 变量。');
    end

    % 确认数据维度：通常是 (通道数 x 采样点数)
    % 如果数据是 (采样点数 x 通道数)，则进行转置
    if size(ecog_data, 1) > size(ecog_data, 2) && size(ecog_data, 2) <= 200 % 假设通道数不会超过200
        ecog_data = ecog_data'; 
        fprintf('  数据已转置为 (通道数 x 采样点数) 格式。\n');
    end
    
    num_channels = size(ecog_data, 1);
    num_samples = size(ecog_data, 2);
    total_duration_sec = num_samples / srate;
    fprintf('  数据总时长: %.2f 秒 (约 %.2f 分钟)\n', total_duration_sec, total_duration_sec / 60);

    % --- 2. 用户输入坏段时间信息 ---
    bad_segments_sec = []; % 存储用户输入的坏段 [起始时间, 结束时间] 矩阵
    
    fprintf('\n--------------------------------------------------------------------------------\n');
    fprintf('请根据您观察到的时域图，输入要去除的肌电（EMG）伪迹坏段时间范围。\n');
    fprintf('**重要提示:** 输入的时间是相对于整个文件的总时长。\n');
    fprintf('**输入格式示例:**\n');
    fprintf('  - **单个坏段:** [100, 105]             (表示从第100秒到第105秒)\n');
    fprintf('  - **多个坏段:** [100, 105; 120.5, 123; 250, 255] (每行一个坏段)\n');
    fprintf('  - **输入完成:** 输入一个空行（直接按回车）然后再次按回车即可。\n');
    fprintf('--------------------------------------------------------------------------------\n');

    while true
        user_input = input('请输入坏段 (秒) [起始时间, 结束时间]: ', 's');
        
        if isempty(user_input)
            break; % 用户输入空行，表示结束输入
        end
        
        try
            segment = str2num(user_input); %#ok<ST2NM> % 尝试将字符串解析为数字矩阵
            
            % 检查解析结果是否有效
            if isempty(segment) || ~ismatrix(segment) || size(segment, 2) ~= 2 || any(segment(:) < 0)
                fprintf('  错误: 输入格式无效。请确保输入为 [起始时间, 结束时间] 形式的数字。\n');
                continue; % 提示用户并继续等待输入
            end
            
            % 检查坏段时间是否超出数据总时长
            if any(segment(:) > total_duration_sec)
                fprintf('  警告: 部分坏段时间超出数据总时长 (%.2f 秒)。已自动裁剪到最大时长。\n', total_duration_sec);
                % 裁剪超出范围的时间点，并确保结束时间不小于起始时间
                segment(segment > total_duration_sec) = total_duration_sec;
                segment(segment(:,1) > segment(:,2), 2) = segment(segment(:,1) > segment(:,2), 1);
            end

            bad_segments_sec = [bad_segments_sec; segment]; %#ok<AGROW> % 将有效输入添加到坏段列表中
            fprintf('  已成功添加坏段: %s\n', mat2str(segment));
        catch ME
            fprintf('  错误: 解析输入失败 (%s)。请检查格式。\n', ME.message);
        end
    end

    % 如果没有指定任何坏段，则直接返回原始数据
    if isempty(bad_segments_sec)
        fprintf('未指定任何坏段。将跳过坏段去除步骤，直接保存原始数据。\n');
        cleaned_ecog_data = ecog_data; 
    else
        fprintf('\n确认要去除的坏段 (秒):\n');
        disp(bad_segments_sec);

        % --- 3. 标记坏段数据为 NaN (Not a Number) ---
        % 将原始数据复制一份，并将其中的坏段部分用NaN填充
        ecog_data_with_nans = double(ecog_data); % 确保数据类型为double，以便存储NaN
        
        for k = 1:size(bad_segments_sec, 1)
            bad_start_sec = bad_segments_sec(k, 1);
            bad_end_sec = bad_segments_sec(k, 2);
            
            % 将秒转换为采样点索引 (MATLAB索引从1开始)
            bad_start_sample = max(1, round(bad_start_sec * srate) + 1);
            bad_end_sample = min(num_samples, round(bad_end_sec * srate));
            
            if bad_start_sample <= bad_end_sample
                % 将所有通道的这个时间段数据设为 NaN
                ecog_data_with_nans(:, bad_start_sample:bad_end_sample) = NaN;
                fprintf('  已在数据中标记坏段 (样本范围): %d 到 %d\n', bad_start_sample, bad_end_sample);
            end
        end
        fprintf('坏段标记为 NaN 完成。这些NaN点将被后续的插值和拼接处理。\n');

        % --- 4. 移除 NaN 区域并进行插值平滑连接 ---
        fprintf('\n正在移除 NaN 区域并对拼接处进行插值平滑...\n');
        cleaned_ecog_data = remove_nan_segments_and_interpolate(ecog_data_with_nans, srate);
        fprintf('坏段移除和插值完成。最终数据形状: %s\n', mat2str(size(cleaned_ecog_data)));
    end

    % --- 5. 保存清理后的数据到新的.mat文件 ---
    [input_folder_path, ~, ~] = fileparts(input_mat_file); % 获取输入文件所在目录
    output_mat_file = fullfile(input_folder_path, [output_prefix, '.mat']);
    
    fprintf('\n正在保存干净信号到文件: %s\n', output_mat_file);
    % 为了兼容您之前的GUI脚本，我们保存为这些变量名
    concatenated_ecog = cleaned_ecog_data; 
    target_sampling_rate = srate; 
    
    save(output_mat_file, 'concatenated_ecog', 'target_sampling_rate', '-v7.3'); % -v7.3 支持大文件
    
    output_file_path = output_mat_file; % 返回输出文件路径

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 坏段去除与保存流程完成。\n');
    fprintf('您现在可以使用此脚本生成的 %s 文件进行后续分析。\n', output_file_path);
    fprintf('--------------------------------------------------\n');

    % --- 辅助函数：核心的NaN移除和插值逻辑 ---
    function cleaned_data_out = remove_nan_segments_and_interpolate(data_with_nans_in, srate_in)
        num_channels_in = size(data_with_nans_in, 1);
        original_data_length_in = size(data_with_nans_in, 2);
        
        % 插值时，从NaN边界向外取0.05秒的正常数据点作为参考
        % 这个参数决定了插值平滑的范围。0.05秒是50ms。
        interp_pad_samples_in = round(50 * srate_in); 

        % 临时用cell数组存储每个通道处理后的数据，因为长度可能不一致
        processed_channels_temp = cell(num_channels_in, 1);

        for ch = 1:num_channels_in
            current_channel_data = data_with_nans_in(ch, :);
            
            % 1. 识别并插值NaN段
            is_nan_segment = isnan(current_channel_data);
            
            % 寻找NaN段的起始和结束索引
            % 技巧：在前后各加一个'false'，确保能检测到从开头或到结尾的NaN段
            padded_is_nan = [false, is_nan_segment, false];
            diff_nan = diff(padded_is_nan);
            
            nan_starts_padded = find(diff_nan == 1); % NaN段的开始索引 (在 padded_is_nan 中)
            nan_ends_padded = find(diff_nan == -1) - 1; % NaN段的结束索引 (在 padded_is_nan 中)
            
            % 准备一个临时通道数据副本，用于插值，插值后仍可能保留NaN
            temp_channel_for_interp = current_channel_data;

            % 执行插值 (在temp_channel_for_interp上进行)
            for seg_k = 1:length(nan_starts_padded)
                nan_seg_start = nan_starts_padded(seg_k);
                nan_seg_end = nan_ends_padded(seg_k);

                % 确定插值参考点
                % x_known 和 y_known 必须在每次循环开始时初始化
                x_known = [];
                y_known = [];

                % 左侧参考点：从NaN段起始点向前找非NaN点
                left_ref_search_end = nan_seg_start - 1;
                left_ref_candidate_start = max(1, nan_seg_start - interp_pad_samples_in);
                
                % 找到实际的非NaN点
                % 寻找从 left_ref_candidate_start 到 left_ref_search_end 之间最新的非NaN点
                valid_indices_left = find(~isnan(current_channel_data(left_ref_candidate_start : left_ref_search_end)));
                if ~isempty(valid_indices_left)
                    left_ref_idx = left_ref_candidate_start + valid_indices_left(end) - 1; % 取最靠近NaN段的那个点
                    x_known = [x_known, left_ref_idx];
                    y_known = [y_known, current_channel_data(left_ref_idx)];
                end

                % 右侧参考点：从NaN段结束点向后找非NaN点
                right_ref_search_start = nan_seg_end + 1;
                right_ref_candidate_end = min(original_data_length_in, nan_seg_end + interp_pad_samples_in);
                
                % 寻找从 right_ref_search_start 到 right_ref_candidate_end 之间最早的非NaN点
                valid_indices_right = find(~isnan(current_channel_data(right_ref_search_start : right_ref_candidate_end)));
                if ~isempty(valid_indices_right)
                    right_ref_idx = right_ref_search_start + valid_indices_right(1) - 1; % 取最靠近NaN段的那个点
                    x_known = [x_known, right_ref_idx];
                    y_known = [y_known, current_channel_data(right_ref_idx)];
                end
                
                % 如果有足够的参考点进行插值
                if length(x_known) >= 2 
                    x_interp = nan_seg_start:nan_seg_end;
                    % 使用 'linear' 插值，并允许 'extrap' 外推（尽管这里应该避免）
                    temp_channel_for_interp(x_interp) = interp1(x_known, y_known, x_interp, 'linear', 'extrap'); 
                elseif length(x_known) == 1 % 只有一侧有参考点，用最近的有效点填充
                    if ~isempty(x_known) % 确保 x_known 确实有值
                        temp_channel_for_interp(nan_seg_start:nan_seg_end) = y_known(1); 
                    end
                else % 没有找到有效参考点 (例如，整个数据都是NaN，或NaN段太长)
                    temp_channel_for_interp(nan_seg_start:nan_seg_end) = 0; % 无法插值，置零
                end
            end
            
            % 将插值后的通道数据（可能仍然包含一些NaN或0，如果插值失败）中的NaN完全移除
            % 这里是最终的“拼接”步骤，只保留非NaN的数据
            processed_channels_temp{ch} = temp_channel_for_interp(~isnan(temp_channel_for_interp));
        end

        % 确保所有通道处理后长度一致
        % 坏段移除可能导致各通道长度不一致，因为每个通道的NaN段可能不同。
        % 为了将它们拼接成一个矩阵，必须使它们长度一致。
        % 这里选择截断到最短通道的长度。
        
        min_cleaned_len_all_channels = Inf;
        if ~isempty(processed_channels_temp) % 确保cell数组不为空
            for ch = 1:num_channels_in
                min_cleaned_len_all_channels = min(min_cleaned_len_all_channels, length(processed_channels_temp{ch}));
            end
        else
            min_cleaned_len_all_channels = 0; % 没有数据
        end

        if min_cleaned_len_all_channels == 0
            cleaned_data_out = zeros(num_channels_in, 1); % 没有有效数据，返回一个全零列向量
            warning('所有通道在坏段去除后均为空，或处理失败。返回一个全零矩阵。');
            return;
        end

        % 最终的输出矩阵
        cleaned_data_out = zeros(num_channels_in, min_cleaned_len_all_channels);
        for ch = 1:num_channels_in
            if length(processed_channels_temp{ch}) >= min_cleaned_len_all_channels
                cleaned_data_out(ch, :) = processed_channels_temp{ch}(1:min_cleaned_len_all_channels);
            else
                % 这种情况不应该发生，因为 min_cleaned_len_all_channels 已经是最小的了
                % 如果出现，说明某个通道在前面步骤中被异常缩短或全NaN
                warning('通道 %d 在坏段去除后长度异常 (小于最短通道)。已用零填充。', ch);
                cleaned_data_out(ch, :) = 0; 
            end
        end
    end

end