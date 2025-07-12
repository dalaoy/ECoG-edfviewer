%% 参数设置
folderPath = 'D:\Download\2025-07-04-胶质瘤大鼠皮层电生理信号采集\Temp_250704_135751';
downsampleRate = 2000;           % 目标采样率
bandpassRange = [1 250];         % 滤波范围
thresholdMultiplier = 6;         % 标准差倍数（伪迹判断）
saveIntermediate = false;        % 是否保存每段处理结果

%% 获取文件列表
files = dir(fullfile(folderPath, '*.mat'));
[~, idx] = sort({files.name});
files = files(idx);
nFiles = length(files);

% 预读取第一个文件获取元信息
f0 = load(fullfile(folderPath, files(1).name));
fs = f0.frequency_parameters.amplifier_sample_rate;
channel_names = {f0.amplifier_channels.native_channel_name};
nChannels = size(f0.amplifier_data, 1);

% 构建滤波器
bpFilt = designfilt('bandpassiir', ...
    'FilterOrder', 4, ...
    'HalfPowerFrequency1', bandpassRange(1), ...
    'HalfPowerFrequency2', bandpassRange(2), ...
    'SampleRate', fs);

% 初始化结果容器
amplifier_cells = cell(1, nFiles);
time_cells = cell(1, nFiles);

%% 处理每段数据
for i = 1:nFiles
    fprintf('处理中：%s\n', files(i).name);
    f = load(fullfile(folderPath, files(i).name));
    data = double(f.amplifier_data);  % 通道 × 点
    t = double(f.t_amplifier);        % 时间戳
    
    % 去伪迹（标准差倍数阈值 + 插值）
    std_vals = std(data, 0, 2);
    threshold = std_vals * thresholdMultiplier;
    artifact_mask = abs(data) > threshold;
    data(artifact_mask) = NaN;
    data = fillmissing(data, 'linear', 2);
    
    % 带通滤波
    data = filtfilt(bpFilt, data')';
    
    % 降采样（使用 downsample 或 resample）
    factor = round(fs / downsampleRate);
    data = downsample(data', factor)';   % data: 通道 × 点
    t = downsample(t, factor);           % 同步时间戳
    
    % 存入 cell
    amplifier_cells{i} = data;
    time_cells{i} = t;

    % 可选：保存每段处理结果（节省内存）
    if saveIntermediate
        save(fullfile(folderPath, ['processed_', num2str(i, '%03d'), '.mat']), 'data', 't', '-v7.3');
    end
end

% 拼接所有段
amplifier_all = cat(2, amplifier_cells{:});  % 通道 × 全部采样点
time_all = cat(2, time_cells{:});            % 1 × 全部时间点
fs = downsampleRate;

disp(['数据已拼接：', num2str(size(amplifier_all,1)), ' 通道 × ', num2str(size(amplifier_all,2)), ' 采样点']);
disp(['处理后采样率：', num2str(fs), ' Hz']);

%% 保存拼接后的结果
outputFile = fullfile(folderPath, 'preprocessed_data.mat');

save(outputFile, ...
    'amplifier_all', ...
    'time_all', ...
    'fs', ...
    'channel_names', ...
    'layout_U5', ...
    'layout_U4', ...
    '-v7.3');  % 使用v7.3支持大数据


