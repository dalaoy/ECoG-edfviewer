function eeg_analysis_pipeline(mat_file, channel_keep, channel_map, electrode_type)
% EEG_ANALYSIS_PIPELINE
% 读取含有 EEG 结构的 .mat 文件，
% 选取指定通道并做CAR去伪迹，
% 调用 pop_spectopo, eegplot 可视化，
% 绘制时频图和高伽马功率热图。
%
% 输入：
%   mat_file       - .mat 文件路径，文件内含 EEG 结构
%   channel_keep   - 保留通道编号（从0开始，如 0:63）
%   channel_map    - 通道布局矩阵，编号从0开始，如 layout_U4 或 layout_U5
%   electrode_type - 字符串，'U4' 或 'U5'，用于热图标题显示
%
% 示例：
% eeg_analysis_pipeline('D:/data/preprocessed.mat', 0:63, layout_U4, 'U4')

% 1. 读取数据
raw = load(mat_file);
if ~isfield(raw, 'EEG')
    error('MAT文件中未找到 EEG 结构');
end
EEG_raw = raw.EEG;

% 提取数据
amplifier_all = squeeze(EEG_raw.data); % [channels x points]
fs = EEG_raw.srate;

% 通道名
channel_names = cell(1, length(EEG_raw.chanlocs));
for i = 1:length(EEG_raw.chanlocs)
    channel_names{i} = EEG_raw.chanlocs(i).labels;
end

% 2. 保留指定通道，channel_keep 从0开始，Matlab索引需+1
idx_keep = channel_keep + 1;
data = amplifier_all(idx_keep, :);

% 3. 进行CAR
CAR = mean(data,1);
data_car = data - CAR;

% 4. 构建 EEG 结构用于 EEGLAB
EEG = [];
EEG.data = reshape(data_car, size(data_car,1), size(data_car,2), 1); % 3D: chan x pnts x trials=1
EEG.nbchan = size(data_car,1);
EEG.pnts = size(data_car,2);
EEG.trials = 1;
EEG.srate = fs;
EEG.xmin = 0;
EEG.xmax = (EEG.pnts-1)/fs;
EEG.chanlocs = struct('labels', channel_names(idx_keep));
EEG.icaweights = [];
EEG.icasphere = [];
EEG.icawinv = [];
EEG.icaact = [];
EEG = eeg_checkset(EEG);

% 5. 频谱图
pop_spectopo(EEG, 1, [0 EEG.xmax*1000], 'EEG', 'freqrange', [1 100], 'electrodes', 'on');

% 6. 时域交互式去伪迹
[~, TMPREJ] = eegplot(EEG.data, 'srate', EEG.srate, ...
    'winlength', 10, 'eloc_file', EEG.chanlocs, ...
    'dispchans', EEG.nbchan, 'reject', 'on');

if ~isempty(TMPREJ)
    EEG.data = eeg_eegrej(EEG.data, TMPREJ);
    EEG.pnts = size(EEG.data, 2);
    EEG = eeg_checkset(EEG);
    fprintf('已去除 %d 段伪迹\n', size(TMPREJ,1));
else
    fprintf('未选择伪迹段，未修改数据\n');
end

% 7. 时频图示例（第1通道）
ch = 1;
signal = squeeze(EEG.data(ch,:,:));
figure;
window = hamming(512);
noverlap = 256;
nfft = 1024;
[s, f, t_spec, p] = spectrogram(signal, window, noverlap, nfft, EEG.srate, 'yaxis');
surf(t_spec, f, 10*log10(abs(p)), 'EdgeColor', 'none');
axis tight; view(0,90);
xlabel('时间 (秒)');
ylabel('频率 (Hz)');
title(sprintf('通道 %d 时频图', ch));
colormap jet; colorbar;

% 8. 高伽马功率热图绘制
targetBand = [70 110];
nChan = EEG.nbchan;
power_values = zeros(1,nChan);

for i = 1:nChan
    sig = squeeze(EEG.data(i,:,:));
    bandFilt = designfilt('bandpassiir', 'FilterOrder', 4, ...
        'HalfPowerFrequency1', targetBand(1), ...
        'HalfPowerFrequency2', targetBand(2), ...
        'SampleRate', fs);
    filtered = filtfilt(bandFilt, sig);
    envelope = abs(hilbert(filtered));
    power_values(i) = mean(envelope.^2);
end

% 生成热图
layoutMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
[nRows, nCols] = size(channel_map);
for r = 1:nRows
    for c = 1:nCols
        ch = channel_map(r,c);
        layoutMap(ch+1) = [r,c]; % 通道号从0开始，MATLAB索引+1
    end
end

power_map = nan(nRows,nCols);
for idx = 1:length(channel_keep)
    ch = channel_keep(idx);
    if isKey(layoutMap, ch)
        pos = layoutMap(ch);
        power_map(pos(1), pos(2)) = power_values(idx);
    end
end

figure;
power_map = flipud(power_map);
imagesc(power_map);
colorbar;
title(sprintf('%s 电极 %.0f–%.0f Hz 平均功率热图', electrode_type, targetBand(1), targetBand(2)));
xlabel('列');
ylabel('行');
axis image;
set(gca, 'YDir', 'normal');
colormap turbo;

end
