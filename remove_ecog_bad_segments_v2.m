function output_file_path = remove_ecog_bad_segments_v2(input_mat_file, output_prefix)
% remove_ecog_bad_segments_v2: 手动标记并去除ECoG信号中的坏段，物理拼接。
%   如果拼接处不连续，则以拼接点为中心去除1s信号并进行局部插值。
%
%   input_mat_file:   输入.mat文件的完整路径。应包含 'concatenated_ecog' 和 'target_sampling_rate'。
%   output_prefix:    输出干净信号.mat文件的前缀名 (例如 'ecog_cleaned_v2').
%
%   输出:
%     output_file_path: 成功保存的干净信号文件的完整路径。
%
%   示例用法:
%     % 假设您的预处理文件是： D:\MyData\Session1\rat_ecog_preprocessed.mat
%     input_data_file = 'D:\MyData\Session1\rat_ecog_preprocessed.mat';
%     output_base_name = 'rat_ecog_emg_cleaned_v2';
%
%     % 调用函数执行清理
%     cleaned_data_file = remove_ecog_bad_segments_v2(input_data_file, output_base_name);
%     fprintf('清理后的数据已保存到: %s\n', cleaned_data_file);

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 坏段去除与局部插值脚本启动 (版本 2)\n');
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

    % --- 3. 执行坏段移除和局部插值 ---
    if isempty(bad_segments_sec)
        fprintf('未指定任何坏段。将跳过坏段去除步骤，直接保存原始数据。\n');
        cleaned_ecog_data = ecog_data; % 没有坏段，直接用原始数据
    else
        fprintf('\n确认要去除的坏段 (秒):\n');
        disp(bad_segments_sec);

        % 首先，物理移除坏段，将数据拼接起来
        fprintf('正在物理移除坏段并拼接...\n');
        [ecog_data_removed_bad_segments, join_indices] = remove_bad_segments_physical(ecog_data, bad_segments_sec, srate);
        fprintf('坏段物理移除完成。数据形状: %s\n', mat2str(size(ecog_data_removed_bad_segments)));

        % 然后，在拼接处进行局部平滑插值
        fprintf('正在检查拼接处并进行局部插值平滑 (中心1秒) ...\n');
        cleaned_ecog_data = smooth_discontinuities_at_joins(ecog_data_removed_bad_segments, join_indices, srate);
        fprintf('局部插值完成。最终数据形状: %s\n', mat2str(size(cleaned_ecog_data)));
    end

    % --- 4. 保存清理后的数据到新的.mat文件 ---
    [input_folder_path, ~, ~] = fileparts(input_mat_file); % 获取输入文件所在目录
    output_mat_file = fullfile(input_folder_path, [output_prefix, '.mat']);
    
    fprintf('\n正在保存干净信号到文件: %s\n', output_mat_file);
    % 为了兼容您之前的GUI脚本，我们保存为这些变量名
    concatenated_ecog = cleaned_ecog_data; 
    target_sampling_rate = srate; 
    
    save(output_mat_file, 'concatenated_ecog', 'target_sampling_rate', '-v7.3'); % -v7.3 支持大文件
    
    output_file_path = output_mat_file; % 返回输出文件路径

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 坏段去除与局部插值流程完成。\n');
    fprintf('您现在可以使用此脚本生成的 %s 文件进行后续分析。\n', output_file_path);
    fprintf('--------------------------------------------------\n');

    % --- 辅助函数 1: 物理移除坏段并记录拼接点 ---
    function [processed_data, join_indices_out] = remove_bad_segments_physical(data_in, bad_segments_sec_in, srate_in)
        num_channels_in = size(data_in, 1);
        original_data_length_in = size(data_in, 2);
        
        % 将坏段转换为样本点索引
        bad_segments_samples = zeros(size(bad_segments_sec_in));
        for k = 1:size(bad_segments_sec_in, 1)
            bad_segments_samples(k, 1) = max(1, round(bad_segments_sec_in(k, 1) * srate_in) + 1);
            bad_segments_samples(k, 2) = min(original_data_length_in, round(bad_segments_sec_in(k, 2) * srate_in));
        end

        % 记录拼接点在“新”数据中的索引
        join_indices_out = []; 
        
        processed_data_cells = cell(num_channels_in, 1);
        
        for ch = 1:num_channels_in
            current_channel_data = data_in(ch, :);
            
            valid_segments_start_end_samples = [];
            current_sample_idx = 1; % 追踪当前处理到的原始数据索引
            
            for k = 1:size(bad_segments_samples, 1)
                bad_start = bad_segments_samples(k, 1);
                bad_end = bad_segments_samples(k, 2);
                
                % 如果坏段在当前处理位置之后，且有有效数据在其之前
                if bad_start > current_sample_idx
                    valid_segments_start_end_samples = [valid_segments_start_end_samples; current_sample_idx, bad_start - 1]; %#ok<AGROW>
                end
                current_sample_idx = bad_end + 1; % 跳过坏段
            end
            
            % 添加最后一个有效段（如果存在）
            if current_sample_idx <= original_data_length_in
                valid_segments_start_end_samples = [valid_segments_start_end_samples; current_sample_idx, original_data_length_in]; %#ok<AGROW>
            end
            
            % 拼接有效数据段
            if isempty(valid_segments_start_end_samples)
                processed_channel_data = [];
            else
                processed_channel_data = [];
                for seg_k = 1:size(valid_segments_start_end_samples, 1)
                    processed_channel_data = [processed_channel_data, current_channel_data(valid_segments_start_end_samples(seg_k, 1):valid_segments_start_end_samples(seg_k, 2))]; %#ok<AGROW>
                end
            end
            processed_data_cells{ch} = processed_channel_data;

            % 记录拼接点在新的 processed_channel_data 中的索引
            if ch == 1 % 只需记录一次，因为所有通道的拼接点都在相同的时间索引
                current_new_idx = 0;
                for k = 1:size(valid_segments_start_end_samples, 1)
                    if k > 1 % 如果是第二个及以后的有效段，说明之前有拼接
                        % 拼接点是当前有效段的起始索引 - 1
                        join_indices_out = [join_indices_out, current_new_idx]; %#ok<AGROW>
                    end
                    current_new_idx = current_new_idx + (valid_segments_start_end_samples(k, 2) - valid_segments_start_end_samples(k, 1) + 1);
                end
            end
        end
        
        % 确保所有通道处理后长度一致，截断到最短的那个
        min_len = min(cellfun(@length, processed_data_cells));
        if min_len == 0
            processed_data = zeros(num_channels_in, 1);
            warning('所有通道在坏段移除后均为空或处理失败。返回一个全零矩阵。');
            return;
        end

        processed_data = zeros(num_channels_in, min_len);
        for ch = 1:num_channels_in
            processed_data(ch, :) = processed_data_cells{ch}(1:min_len);
        end
    end

    % --- 辅助函数 2: 在拼接处进行局部平滑插值 ---
    function smoothed_data = smooth_discontinuities_at_joins(data_in, join_indices_in, srate_in)
        smoothed_data = double(data_in); % 确保数据类型为double
        num_channels_in = size(data_in, 1);
        
        % 定义局部插值的窗口大小 (总长度 1 秒)
        interp_window_sec = 1.0; 
        interp_half_window_samples = round((interp_window_sec / 2) * srate_in);
        
        % 不连续的判断阈值 (例如，前后10个采样点平均幅值的差异超过某个标准差倍数)
        % 这需要根据你的信号特性调整。这里使用一个启发式方法：
        % 如果前后0.1秒的平均值差异超过信号整体标准差的5倍，则认为是断裂
        discontinuity_threshold_factor = 5; 
        
        % 计算每个通道的整体标准差（用于不连续判断）
        channel_std_devs = std(data_in, 0, 2); 
        
        % 如果数据是常数，std会是0，避免除零
        channel_std_devs(channel_std_devs == 0) = mean(channel_std_devs(channel_std_devs ~=0));
        if any(channel_std_devs == 0) % If still zeros (e.g., all channels constant)
             channel_std_devs = ones(size(channel_std_devs)); % Use 1 as a default
        end


        fprintf('  局部插值窗口: %g 秒 (%d 采样点). 不连续判断阈值: %g x 标准差。\n', ...
                interp_window_sec, 2 * interp_half_window_samples, discontinuity_threshold_factor);

        for ch = 1:num_channels_in
            current_channel_data = data_in(ch, :);
            
            for k = 1:length(join_indices_in)
                join_point_idx = join_indices_in(k); % 拼接点是后一段的第一个点的前一个点
                
                % 确保拼接点有效且不是数据边缘
                if join_point_idx < 1 || join_point_idx >= size(data_in, 2)
                    continue;
                end
                
                % 获取拼接点前后的信号值
                value_before_join = current_channel_data(join_point_idx);
                value_after_join = current_channel_data(join_point_idx + 1); % 后一段的第一个点

                % 计算前后小段的平均值进行不连续判断
                % 取前后 0.1s 的数据来计算平均值
                check_window_samples = round(0.1 * srate_in);
                
                idx_before_check_start = max(1, join_point_idx - check_window_samples);
                idx_before_check_end = join_point_idx;
                
                idx_after_check_start = join_point_idx + 1;
                idx_after_check_end = min(size(data_in, 2), join_point_idx + 1 + check_window_samples);
                
                mean_before = mean(current_channel_data(idx_before_check_start : idx_before_check_end));
                mean_after = mean(current_channel_data(idx_after_check_start : idx_after_check_end));

                % 判断是否存在不连续性
                if abs(mean_after - mean_before) > (discontinuity_threshold_factor * channel_std_devs(ch))
                    fprintf('    通道 %d: 在拼接点 %d 处检测到不连续 (差异: %.2f)。正在进行局部插值。\n', ...
                            ch, join_point_idx, abs(mean_after - mean_before));

                    % 定义需要插值的局部范围 (以拼接点为中心，前后各 interp_half_window_samples)
                    interp_start_sample = max(1, join_point_idx - interp_half_window_samples + 1);
                    interp_end_sample = min(size(data_in, 2), join_point_idx + interp_half_window_samples);
                    
                    % 确保插值范围不覆盖其他拼接点
                    % (这里没有实现，因为假设拼接点之间距离足够远)

                    % 确定插值参考点
                    % 左侧参考点：插值范围前的最后一个点
                    x_left_ref = interp_start_sample - 1;
                    y_left_ref = current_channel_data(x_left_ref); % 使用插值范围前一个点

                    % 右侧参考点：插值范围后的第一个点
                    x_right_ref = interp_end_sample + 1;
                    y_right_ref = current_channel_data(x_right_ref); % 使用插值范围后一个点
                    
                    % 确保参考点在数据范围内
                    if x_left_ref < 1
                        x_left_ref = 1; y_left_ref = current_channel_data(1);
                    end
                    if x_right_ref > size(data_in, 2)
                        x_right_ref = size(data_in, 2); y_right_ref = current_channel_data(end);
                    end


                    % 检查参考点是否是同一个点
                    if x_left_ref >= x_right_ref
                        % 这意味着整个信号太短，或者拼接点在非常边缘
                        % 无法进行有效的两点插值，直接用左侧值填充
                        smoothed_data(ch, interp_start_sample:interp_end_sample) = y_left_ref;
                        continue;
                    end

                    % 实际插值
                    x_interp_range = interp_start_sample : interp_end_sample;
                    x_known = [x_left_ref, x_right_ref];
                    y_known = [y_left_ref, y_right_ref];
                    
                    smoothed_data(ch, x_interp_range) = interp1(x_known, y_known, x_interp_range, 'linear', 'extrap');
                end
            end
        end
    end

end