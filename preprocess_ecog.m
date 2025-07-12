function preprocess_ecog(input_folder, output_filename_prefix, target_sampling_rate)
% preprocess_ecog 对大鼠ECoG信号进行预处理。
%
%   输入参数:
%     input_folder (string): 包含原始.mat文件的文件夹路径。
%     output_filename_prefix (string): 输出文件的前缀名，将生成 .mat 文件。
%     target_sampling_rate (double): 目标降采样率，单位Hz (例如 2000)。
%
%   示例用法:
%     preprocess_ecog('D:\RatECoGData\Session1_20231026', 'rat_ecog_preprocessed', 2000);

    if nargin < 3
        error('请提供输入文件夹路径、输出文件前缀和目标采样率。');
    end

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 信号预处理开始...\n');
    fprintf('输入文件夹: %s\n', input_folder);
    fprintf('目标采样率: %d Hz\n', target_sampling_rate);
    fprintf('--------------------------------------------------\n');

    all_preprocessed_data = {}; % 用于存储每个文件处理后的数据
    
    % 获取文件夹中所有 .mat 文件
    mat_files = dir(fullfile(input_folder, '*.mat'));
    
    if isempty(mat_files)
        fprintf('错误: 在 %s 中未找到任何 .mat 文件。请检查路径或文件类型。\n', input_folder);
        return;
    end

    % 遍历每个 .mat 文件
    for i = 1:length(mat_files)
        file_name = mat_files(i).name;
        file_path = fullfile(input_folder, file_name);
        
        fprintf('正在处理文件: %s\n', file_name);
        
        try
            % 1. 加载数据
            data_struct = load(file_path);
            
            % 确定ECoG数据变量名
            if isfield(data_struct, 'amplifier_data')
                raw_ecog = data_struct.amplifier_data;
            else
                fprintf('警告: 文件 %s 中未找到 ''amplifier_data'' 变量。跳过此文件。\n', file_name);
                continue;
            end
            
            % 确定原始采样率
            original_sampling_rate = []; % Initialize to empty
            if isfield(data_struct, 'frequency_parameters') && isfield(data_struct.frequency_parameters, 'amplifier_sample_rate')
                original_sampling_rate = data_struct.frequency_parameters.amplifier_sample_rate(1); % Accessing the field within the struct
            end
            
            if isempty(original_sampling_rate)
                % Fallback if sampling rate not found in frequency_parameters
                % Try to infer from filename (e.g., "20k" or "5k")
                if contains(lower(file_name), '20k')
                    original_sampling_rate = 20000;
                elseif contains(lower(file_name), '5k')
                    original_sampling_rate = 5000;
                else
                    fprintf('警告: 无法从文件 %s 中确定原始采样率。跳过此文件。\n', file_name);
                    continue;
                end
            end

            % Ensure original_sampling_rate is a scalar double
            if ~isscalar(original_sampling_rate)
                 fprintf('警告: 原始采样率不是标量，尝试使用第一个值。文件: %s\n', file_name);
                 original_sampling_rate = original_sampling_rate(1);
            end


            % Ensure raw_ecog data is in (channels x samples) format
            % Based on your output, 'amplifier_data' is already [128 1200000], which is channels x samples
            % So, no transpose should be needed here unless you've changed the loading behavior.
            % However, it's good practice to ensure consistency.
            if size(raw_ecog, 1) > size(raw_ecog, 2) && size(raw_ecog, 2) == 128 % Heuristic for (samples x channels)
                raw_ecog = raw_ecog'; % Transpose to (channels x samples)
                fprintf('  数据已转置为 (通道数 x 采样点数) 格式。\n');
            end
            
            fprintf('  原始采样率: %d Hz, 数据形状: %s\n', original_sampling_rate, mat2str(size(raw_ecog)));

            % 2. 降采样
            [P, Q] = rat(target_sampling_rate / original_sampling_rate);
            % resample operates on columns, so if raw_ecog is (channels x samples),
            % we need to transpose, resample, then transpose back.
            resampled_ecog = resample(raw_ecog', P, Q)';
            
            fprintf('  降采样完成：从 %d Hz 到 %d Hz. 新的数据点数: %d\n', ...
                    original_sampling_rate, target_sampling_rate, size(resampled_ecog, 2));

            % 3. 滤波
            nyquist = target_sampling_rate / 2;

            % 0.1 Hz 高通滤波 (去除低频漂移)
            d_hp = designfilt('highpassiir','FilterOrder',4,'HalfPowerFrequency',0.1,...
                              'SampleRate',target_sampling_rate);
            filtered_ecog = filtfilt(d_hp, resampled_ecog')';

            % 50 Hz 陷波滤波及谐波去除
            notch_freqs = [50, 100, 150]; % 50Hz及其谐波
            for nf = notch_freqs
                if nf < nyquist
                    d_notch = designfilt('bandstopiir','FilterOrder',4, ...
                                         'HalfPowerFrequency1',nf-2,'HalfPowerFrequency2',nf+2, ...
                                         'SampleRate',target_sampling_rate);
                    filtered_ecog = filtfilt(d_notch, filtered_ecog')';
                end
            end
            fprintf('  滤波完成：0.1Hz高通和50Hz陷波及其谐波去除。\n');

            % 4. 去伪迹 (阈值法 + 插值平滑)
            artifact_free_ecog = filtered_ecog;
            num_channels = size(filtered_ecog, 1);
            
            mad_threshold_factor = 7; % Adjust this value as needed (e.g., from 5 to 10)
            
            for ch = 1:num_channels
                channel_data = filtered_ecog(ch, :);
                
                median_val = median(channel_data);
                mad_val = median(abs(channel_data - median_val));
                
                if mad_val < 1e-9 % Small threshold to avoid division by zero or very tiny MAD
                    threshold = mad_threshold_factor * std(channel_data);
                else
                    threshold = mad_threshold_factor * mad_val;
                end
                
                artifact_indices = find(abs(channel_data - median_val) > threshold);
                
                if ~isempty(artifact_indices)
                    % Convert indices to logical mask for easier segmenting
                    is_artifact = false(size(channel_data));
                    is_artifact(artifact_indices) = true;

                    % Find start and end of continuous artifact segments
                    % Pad with false to catch leading/trailing segments
                    padded_is_artifact = [false, is_artifact, false];
                    diff_artifact = diff(padded_is_artifact);

                    start_indices = find(diff_artifact == 1); % Artifact starts
                    end_indices = find(diff_artifact == -1) - 1; % Artifact ends

                    for seg_idx = 1:length(start_indices)
                        seg_start = start_indices(seg_idx);
                        seg_end = end_indices(seg_idx);

                        % Determine interpolation boundary points
                        interp_x_vals = [];
                        interp_y_vals = [];

                        % Point before artifact segment
                        if seg_start > 1
                            interp_x_vals = [interp_x_vals, seg_start - 1];
                            interp_y_vals = [interp_y_vals, channel_data(seg_start - 1)];
                        end
                        
                        % Point after artifact segment
                        if seg_end < length(channel_data)
                            interp_x_vals = [interp_x_vals, seg_end + 1];
                            interp_y_vals = [interp_y_vals, channel_data(seg_end + 1)];
                        end

                        % Perform interpolation if valid boundary points exist
                        if length(interp_x_vals) >= 2
                            x_to_interp = seg_start:seg_end;
                            artifact_free_ecog(ch, x_to_interp) = interp1(interp_x_vals, interp_y_vals, x_to_interp, 'linear', 'extrap');
                        elseif ~isempty(interp_x_vals) % Only one boundary point
                             % Fill with the value of the single boundary point
                             artifact_free_ecog(ch, seg_start:seg_end) = interp_y_vals(1);
                        else % No boundary points (e.g., entire signal is artifact, or artifact at extreme ends)
                             % In this case, signal remains unchanged for this segment
                             % Or you might choose to set to NaN or 0, depending on your needs
                        end
                    end
                end
            end
            fprintf('  伪迹去除和插值完成。\n');
            
            all_preprocessed_data{end+1} = artifact_free_ecog;

        catch ME
            fprintf('处理文件 %s 时发生错误: %s\n', file_name, ME.message);
            continue; 
        end
    end

    if isempty(all_preprocessed_data)
        fprintf('没有成功处理任何文件，无法进行拼接。预处理结束。\n');
        return;
    end

    % 5. 拼接所有处理后的文件
    num_channels = size(all_preprocessed_data{1}, 1);
    valid_data_blocks = {};
    for k = 1:length(all_preprocessed_data)
        if size(all_preprocessed_data{k}, 1) == num_channels
            valid_data_blocks{end+1} = all_preprocessed_data{k};
        else
            fprintf('警告: 文件 %s 的通道数 (%d) 与第一个文件 (%d) 不同，跳过拼接。\n', ...
                    mat_files(k).name, size(all_preprocessed_data{k}, 1), num_channels);
        end
    end
    
    if isempty(valid_data_blocks)
        fprintf('由于通道数不匹配，没有可拼接的有效数据。预处理结束。\n');
        return;
    end

    concatenated_ecog = cat(2, valid_data_blocks{:}); % In the time dimension
    fprintf('所有有效文件拼接完成。总数据形状: %s\n', mat2str(size(concatenated_ecog)));

    % 6. 保存拼接后的数据
    output_mat_filepath = fullfile(input_folder, [output_filename_prefix, '_preprocessed.mat']);
    save(output_mat_filepath, 'concatenated_ecog', 'target_sampling_rate', '-v7.3');
    fprintf('拼接后的数据已保存到: %s\n', output_mat_filepath);

    fprintf('提示: 如果需要EDF格式，您可能需要使用EEGLAB等第三方工具箱进行转换。\n');

    fprintf('--------------------------------------------------\n');
    fprintf('ECoG 信号预处理完成。\n');
    fprintf('--------------------------------------------------\n');

end