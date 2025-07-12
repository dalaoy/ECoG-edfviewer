% %% 参数设置
% folderPath = 'D:\Download\2025-07-04-胶质瘤大鼠皮层电生理信号采集\Temp_250704_140458';
% downsampleRate = 2000;           % 目标采样率
% bandpassRange = [1 250];         % 滤波范围
% thresholdMultiplier = 6;         % MAD 阈值倍数
% saveIntermediate = false;        % 是否保存每段处理结果
% load(fullfile(folderPath, 'preprocessed_data.mat')); % 需包含 amplifier_all, fs, channel_names
% 
% %% 只取前64通道（channelmap 0~63对应 MATLAB索引1~64）
% channels_use = 0:63;
% channels_use_idx = channels_use + 1;
% signal_64ch = amplifier_all(channels_use_idx, :);
% 
% %% CAR处理
% mean_signal = mean(signal_64ch, 1);
% signal_64ch_CAR = signal_64ch - mean_signal;
% 
% %% 通道数更新
% nChannels = length(channels_use);
% 
% %% 显示所有通道时域图（64通道CAR信号）
% figure;
% offset = 100; % 通道间偏移
% hold on;
% for ch = 1:nChannels
%     plot((1:length(signal_64ch_CAR(ch,:))) / fs, signal_64ch_CAR(ch,:) + (ch-1)*offset);
% end
% xlabel('Time (s)'); ylabel('Channels');
% title('前64通道CAR信号时域图');
% hold off;
% 
% %% 可视化（选择通道示例）
% channel_id = 1; % 1~64范围内
% signal = signal_64ch_CAR(channel_id, :);
% 
% % 时频图
% figure;
% window = hamming(512);
% noverlap = 256;
% nfft = 1024;
% [s, f, t_spec, p] = spectrogram(signal, window, noverlap, nfft, fs, 'yaxis');
% surf(t_spec, f, 10*log10(abs(p)), 'EdgeColor', 'none');
% axis tight; view(0,90);
% xlabel('Time (s)'); ylabel('Frequency (Hz)');
% title(['通道: ', channel_names{channels_use_idx(channel_id)}, ' - 时频图']);
% colormap jet; colorbar;
% 
% % 频谱图
% figure;
% n = length(signal);
% Y = abs(fft(signal));
% f_fft = (0:n-1)*(fs/n);
% plot(f_fft(1:floor(n/2)), Y(1:floor(n/2)));
% xlabel('Frequency (Hz)'); ylabel('Amplitude');
% title(['通道: ', channel_names{channels_use_idx(channel_id)}, ' - 频谱']);
% 
% %% 热图生成
% electrode_type = 'U4';  % 或 'U5'
% 
% layout_U5 = [... % 0-based通道号，原始数据
%     124, 100, 83,  116;
%     101,  90, 106, 108;
%     126, 95,  79,  118;
%      99, 71,  85,  104;
%     122,  91, 77,  114;
%      97,  69, 84,  107;
%     120,  87,  72, 112;
%     103,  66,  78, 110;
%     102,  64,  81, 111;
%     121,  70,  74, 113;
%      92,  68,  80,  88;
%     127,  89,  76, 119;
%      94,  67, 105,  82;
%     125,  93,  75, 117;
%      96,  65, 109,  86;
%     123,  98,  73, 115
% ];
% 
% layout_U4 = [
%     11, 21,  37, 3;
%     19, 47, 27, 26;
%      9, 22, 56,  1;
%     23, 48, 38, 28;
%     13, 44, 58,  5;
%     20, 50, 34, 30;
%     15, 46, 63,  7;
%     17, 53, 57, 24;
%     16, 55, 40, 25;
%     14, 49, 61,  6;
%     42, 51, 36, 35;
%      8, 39, 59,  0;
%     45, 52, 31, 33;
%     10, 43, 60,  2;
%     41, 54, 29, 32;
%     12, 18, 62,  4
% ];
% 
% switch electrode_type
%     case 'U5'
%         layout_matrix = layout_U5;
%     case 'U4'
%         layout_matrix = layout_U4;
%     otherwise
%         error('未知电极类型，请选择 ''U5'' 或 ''U4''');
% end
% 
% %% 目标频段功率计算
% targetBand = [70 110];
% power_values = zeros(1, nChannels);
% 
% for ch = 1:nChannels
%     signal = signal_64ch_CAR(ch, :);
%     bandFilt = designfilt('bandpassiir', ...
%         'FilterOrder', 4, ...
%         'HalfPowerFrequency1', targetBand(1), ...
%         'HalfPowerFrequency2', targetBand(2), ...
%         'SampleRate', fs);
%     filtered = filtfilt(bandFilt, signal);
%     envelope = abs(hilbert(filtered));
%     power_values(ch) = mean(envelope.^2);
% end
% 
% fprintf('\n每通道 %.0f–%.0f Hz 平均功率：\n', targetBand(1), targetBand(2));
% fprintf('通道\t功率(μV^2)\n');
% fprintf('--------------------\n');
% for ch = 1:nChannels
%     fprintf('%3d\t%.3f\n', ch, power_values(ch));
% end
% 
% %% layout_matrix通道号由0-base转成1-base（只保留0~63通道）
% layout_matrix_corrected = layout_matrix + 1;
% 
% % 把不在0~63范围的通道设为NaN
% layout_matrix_corrected(~ismember(layout_matrix_corrected, 1:nChannels)) = NaN;
% 
% [nRows, nCols] = size(layout_matrix_corrected);
% power_map = nan(nRows, nCols);
% 
% for r = 1:nRows
%     for c = 1:nCols
%         ch = layout_matrix_corrected(r, c);
%         if ~isnan(ch)
%             power_map(r, c) = power_values(ch);
%         end
%     end
% end
% 
% %% 绘制热图
% figure;
% power_map_flip = flipud(power_map);
% imagesc(power_map_flip);
% colorbar;
% title(sprintf('%s电极 - %.0f–%.0f Hz 平均功率热图', electrode_type, targetBand(1), targetBand(2)));
% xlabel('Column'); ylabel('Row');
% axis image;
% set(gca, 'YDir', 'normal');
% colormap turbo;

% 指定你的.mat文件路径
mat_file = 'D:\Download\2025-07-04-胶质瘤大鼠皮层电生理信号采集\Temp_250704_135751\preprocessed_data_eeglabver.mat';

% 仅保留前64个通道（例子）
channel_keep = 0:63;  % 注意：这里是原始通道编号

% 选择你的电极布局（例如 U4）
layout_U4 = [...  % 复制你之前的布局矩阵
    11, 21, 37, 3;
    19, 47, 27, 26;
    ... 等
];
electrode_type = 'U4';

% 调用分析流程
eeg_analysis_pipeline(mat_file, channel_keep, layout_U4, electrode_type);

