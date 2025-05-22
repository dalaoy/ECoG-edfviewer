classdef ECoGAnalysisApp < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure            matlab.ui.Figure
        GridLayout          matlab.ui.container.GridLayout

        % 左侧控制面板元素
        ControlPanel        matlab.ui.container.Panel
        LoadECoGButton      matlab.ui.control.Button
        ECoGFilePathLabel   matlab.ui.control.Label
        LoadEMGButton       matlab.ui.control.Button
        EMGFilePathLabel    matlab.ui.control.Label
        ChannelListBoxLabel matlab.ui.control.Label
        ChannelListBox      matlab.ui.control.ListBox % 将支持多选
        AnalyzeChannelButton matlab.ui.control.Button
        
        % 新增：处理操作面板 (未来用于滤波和参考)
        ProcessingPanel     matlab.ui.container.Panel
        FilterTypeDropDownLabel matlab.ui.control.Label
        FilterTypeDropDown  matlab.ui.control.DropDown
        CutoffFreq1Label    matlab.ui.control.Label
        CutoffFreq1EditField matlab.ui.control.NumericEditField
        CutoffFreq2Label    matlab.ui.control.Label
        CutoffFreq2EditField matlab.ui.control.NumericEditField
        FilterOrderLabel    matlab.ui.control.Label
        FilterOrderEditField matlab.ui.control.NumericEditField
        ApplyFilterButton   matlab.ui.control.Button
        ApplyCARButton      matlab.ui.control.Button
        ResetProcessingButton matlab.ui.control.Button
        ProcessingStatusLabel matlab.ui.control.Label


        % 右侧显示面板元素 (使用 TabGroup)
        DisplayTabGroup     matlab.ui.container.TabGroup
        TimeDomainTab       matlab.ui.container.Tab
        TimeDomainGridLayout matlab.ui.container.GridLayout
        ECoGAxes            matlab.ui.control.UIAxes
        EMGAxes             matlab.ui.control.UIAxes
        
        TimeFrequencyTab    matlab.ui.container.Tab
        SpectrogramGridContainer matlab.ui.container.GridLayout % 新属性：可滚动的父grid
        
        PowerSpectrumTab    matlab.ui.container.Tab
        PSDGridContainer    matlab.ui.container.GridLayout % 新属性：可滚动的父grid
    end

    % Properties to store data
    properties (Access = private)
        ecog_data_raw       % 存储原始加载的ECoG数据
        ecog_data_filtered  % 存储滤波后的ECoG数据
        ecog_data           % 当前用于显示和分析的ECoG数据 (可能是原始、滤波后或参考后)
        ecog_srate
        ecog_chanlocs       % Cell array of channel labels

        emg_data
        emg_srate
        emg_chanlocs        % Cell array of channel labels
        
        isFilterApplied     matlab.lang.OnOffSwitchState = 'off'
        isCARApplied        matlab.lang.OnOffSwitchState = 'off'
        lastFilterParams    struct % 存储上次应用的滤波器参数
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: LoadECoGButton
        function LoadECoGButtonPushed(app, event)
            [filename, filepath] = uigetfile({'*.edf;*.EDF', 'EDF Files (*.edf, *.EDF)'; '*.*', 'All Files (*.*)'}, ...
                                             'Select ECoG EDF File');
            if isequal(filename, 0) || isequal(filepath, 0)
                uialert(app.UIFigure, 'User cancelled ECoG file selection.', 'Info');
                return;
            end
            fullpathname = fullfile(filepath, filename);
            app.ECoGFilePathLabel.Text = ['ECoG: ', filename];

            try
                [data_temp, Hdr] = sload(fullpathname); 

                if isempty(data_temp) || isempty(Hdr)
                    error('sload did not return data or header.');
                end

                if size(data_temp,1) == Hdr.NS 
                   raw_data = data_temp;
                elseif size(data_temp,2) == Hdr.NS 
                   raw_data = data_temp'; 
                else
                   error('Mismatch between data dimensions and number of channels in header from sload.');
                end
                app.ecog_data_raw = raw_data; % Store raw data
                app.ecog_data_filtered = app.ecog_data_raw; % Initially filtered is same as raw
                app.ecog_data = app.ecog_data_raw;    % Active data is initially raw


                if isfield(Hdr, 'SampleRate') && ~isempty(Hdr.SampleRate)
                    if length(Hdr.SampleRate) == Hdr.NS
                        app.ecog_srate = Hdr.SampleRate(1);
                        if ~all(Hdr.SampleRate == app.ecog_srate)
                            uialert(app.UIFigure, 'ECoG channels have different sampling rates. Using the first one. Processing might be incorrect.', 'Warning', 'Interpreter', 'none');
                        end
                    elseif length(Hdr.SampleRate) == 1
                        app.ecog_srate = Hdr.SampleRate;
                    else
                        error('Cannot determine ECoG sampling rate from sload header (Hdr.SampleRate format unknown).');
                    end
                elseif isfield(Hdr, 'SPR') 
                    if isfield(Hdr, 'Dur') && Hdr.Dur(1) ~= 0
                        app.ecog_srate = Hdr.SPR(1) / Hdr.Dur(1);
                         if ~all( (Hdr.SPR ./ Hdr.Dur) == app.ecog_srate) 
                             uialert(app.UIFigure, 'ECoG channels have different sampling rates calculated from SPR/Dur. Using the first one.', 'Warning', 'Interpreter', 'none');
                        end
                    else
                        app.ecog_srate = Hdr.SPR(1); 
                        uialert(app.UIFigure, 'ECoG sampling rate determined from SPR without Duration. May be inaccurate if record duration is not 1s.', 'Warning', 'Interpreter', 'none');
                    end
                else
                    error('Cannot determine ECoG sampling rate from sload header (SampleRate or SPR not found).');
                end

                if isfield(Hdr, 'Label') && ~isempty(Hdr.Label)
                    app.ecog_chanlocs = cellstr(Hdr.Label); 
                else
                    app.ecog_chanlocs = arrayfun(@(x) sprintf('Ch %d', x), 1:size(app.ecog_data,1), 'UniformOutput', false);
                end
                app.ecog_chanlocs = strtrim(app.ecog_chanlocs);
                emptyLabels = cellfun('isempty', app.ecog_chanlocs);
                for k_idx = find(emptyLabels)'
                    app.ecog_chanlocs{k_idx} = sprintf('Ch %d', k_idx);
                end
                
                app.isFilterApplied = 'off'; % Reset states
                app.isCARApplied = 'off';
                app.updateProcessingStatusLabel();

                app.updateChannelListBox();
                app.plotTimeDomainECoG();
                uialert(app.UIFigure, 'ECoG data loaded successfully using sload!', 'Success', 'Interpreter', 'none');

            catch ME
                uialert(app.UIFigure, ['Error loading ECoG with sload: ', ME.message], 'Error', 'Interpreter', 'none');
                fprintf('Error loading ECoG with sload. Details:\n%s\n', ME.getReport('extended', 'hyperlinks','off'));
                app.ECoGFilePathLabel.Text = 'ECoG: Failed to load';
                app.ecog_data_raw = []; app.ecog_data_filtered = []; app.ecog_data = []; 
                app.ecog_chanlocs = {};
                app.updateChannelListBox();
                cla(app.ECoGAxes); title(app.ECoGAxes, 'ECoG Signals');
            end
        end

        % Button pushed function: LoadEMGButton (similar logic, not detailed for brevity now)
        function LoadEMGButtonPushed(app, event)
            [filename, filepath] = uigetfile({'*.edf;*.EDF', 'EDF Files (*.edf, *.EDF)'; '*.*', 'All Files (*.*)'}, ...
                                             'Select EMG EDF File');
            if isequal(filename, 0) || isequal(filepath, 0)
                uialert(app.UIFigure, 'User cancelled EMG file selection.', 'Info');
                return;
            end
            fullpathname = fullfile(filepath, filename);
            app.EMGFilePathLabel.Text = ['EMG: ', filename];
            try
                [data_temp, Hdr] = sload(fullpathname);
                if isempty(data_temp) || isempty(Hdr), error('sload did not return data or header for EMG.'); end
                if size(data_temp,1) == Hdr.NS, app.emg_data = data_temp;
                elseif size(data_temp,2) == Hdr.NS, app.emg_data = data_temp';
                else, error('Mismatch between EMG data dimensions and number of channels in header.'); end

                if isfield(Hdr, 'SampleRate') && ~isempty(Hdr.SampleRate)
                    if length(Hdr.SampleRate) == Hdr.NS, app.emg_srate = Hdr.SampleRate(1);
                        if ~all(Hdr.SampleRate == app.emg_srate), uialert(app.UIFigure, 'EMG channels different Srates.', 'Warning','Interpreter','none'); end
                    elseif length(Hdr.SampleRate) == 1, app.emg_srate = Hdr.SampleRate;
                    else, error('Cannot determine EMG Srate.'); end
                elseif isfield(Hdr, 'SPR')
                    if isfield(Hdr, 'Dur') && Hdr.Dur(1) ~= 0, app.emg_srate = Hdr.SPR(1) / Hdr.Dur(1);
                        if ~all((Hdr.SPR ./ Hdr.Dur) == app.emg_srate), uialert(app.UIFigure, 'EMG channels different Srates (SPR/Dur).', 'Warning','Interpreter','none'); end
                    else, app.emg_srate = Hdr.SPR(1); uialert(app.UIFigure, 'EMG Srate from SPR may be inaccurate.', 'Warning','Interpreter','none'); end
                else, error('Cannot determine EMG Srate.'); end
                
                if isfield(Hdr, 'Label') && ~isempty(Hdr.Label), app.emg_chanlocs = cellstr(Hdr.Label);
                else, app.emg_chanlocs = arrayfun(@(x) sprintf('EMG Ch %d',x),1:size(app.emg_data,1),'UniformOutput',false); end
                app.emg_chanlocs = strtrim(app.emg_chanlocs);
                emptyLabels = cellfun('isempty', app.emg_chanlocs);
                for k_idx = find(emptyLabels)', app.emg_chanlocs{k_idx} = sprintf('EMG Ch %d', k_idx); end
                
                app.plotTimeDomainEMG();
                uialert(app.UIFigure, 'EMG data loaded successfully using sload!', 'Success','Interpreter','none');
            catch ME
                uialert(app.UIFigure, ['Error loading EMG: ', ME.message], 'Error','Interpreter','none');
                fprintf('Error loading EMG. Details:\n%s\n', ME.getReport('extended', 'hyperlinks','off'));
                app.EMGFilePathLabel.Text = 'EMG: Failed to load'; app.emg_data = [];
                cla(app.EMGAxes); title(app.EMGAxes, 'EMG Signals');
            end
        end

        % Function to update channel list box
        function updateChannelListBox(app)
            if ~isempty(app.ecog_data) && ~isempty(app.ecog_chanlocs) && iscell(app.ecog_chanlocs)
                app.ChannelListBox.Items = app.ecog_chanlocs;
                % For multi-select, Value should be a cell array of strings
                % If you want a default selection, you can set it, e.g.:
                if ~isempty(app.ChannelListBox.Items)
                     app.ChannelListBox.Value = {app.ChannelListBox.Items{1}}; % Default to first channel selected
                else
                    app.ChannelListBox.Value = {};
                end
            else
                app.ChannelListBox.Items = {};
                app.ChannelListBox.Value = {};
            end
        end

        % Function to plot ECoG time domain (uses app.ecog_data)
        function plotTimeDomainECoG(app)
            if isempty(app.ecog_data) || isempty(app.ecog_srate)
                cla(app.ECoGAxes); title(app.ECoGAxes, 'ECoG Signals'); xlabel(app.ECoGAxes, 'Time (s)'); ylabel(app.ECoGAxes, 'Channels');
                return;
            end
            cla(app.ECoGAxes);
            hold(app.ECoGAxes, 'on');
            [nChannels, nSamples] = size(app.ecog_data);
            time_vec = (0:nSamples-1) / app.ecog_srate;
            
            valid_data_for_scaling = app.ecog_data(~any(isnan(app.ecog_data), 2), :);
            if isempty(valid_data_for_scaling)
                offset_scale = 1; 
            else
                offset_scale = max(abs(valid_data_for_scaling(:))) * 1.5;
            end
            if offset_scale == 0, offset_scale = 1; end 

            for i = 1:nChannels
                plot(app.ECoGAxes, time_vec, app.ecog_data(i, :) + (nChannels-i)*offset_scale);
            end
            hold(app.ECoGAxes, 'off');

            yticks_pos = (0:nChannels-1)*offset_scale;
            yticks_labels = cell(1, nChannels);
            if ~isempty(app.ecog_chanlocs) && length(app.ecog_chanlocs) == nChannels
                for i=1:nChannels
                    yticks_labels{i} = app.ecog_chanlocs{nChannels-i+1}; 
                end
            else
                 for i=1:nChannels
                    yticks_labels{i} = sprintf('Ch %d', nChannels-i+1); 
                end
            end
            
            set(app.ECoGAxes, 'YTick', sort(yticks_pos), 'YTickLabel', yticks_labels); 

            xlabel(app.ECoGAxes, 'Time (s)');
            ylabel(app.ECoGAxes, 'Channels');
            title(app.ECoGAxes, 'ECoG Time Domain Signals');
            axis(app.ECoGAxes, 'tight');
            if ~isempty(app.EMGAxes.Children) 
                app.linkTimeAxes();
            end
        end

        % Function to plot EMG time domain
        function plotTimeDomainEMG(app)
            if isempty(app.emg_data) || isempty(app.emg_srate)
                cla(app.EMGAxes); title(app.EMGAxes, 'EMG Signals'); xlabel(app.EMGAxes, 'Time (s)'); ylabel(app.EMGAxes, 'Channels');
                return;
            end
            cla(app.EMGAxes);
            hold(app.EMGAxes, 'on');
            [nChannels, nSamples] = size(app.emg_data);
            time_vec = (0:nSamples-1) / app.emg_srate;

            valid_data_for_scaling = app.emg_data(~any(isnan(app.emg_data), 2), :);
            if isempty(valid_data_for_scaling), offset_scale = 1;
            else, offset_scale = max(abs(valid_data_for_scaling(:))) * 1.5; end
            if offset_scale == 0, offset_scale = 1; end

            for i = 1:nChannels
                plot(app.EMGAxes, time_vec, app.emg_data(i, :) + (nChannels-i)*offset_scale);
            end
            hold(app.EMGAxes, 'off');
            
            yticks_pos = (0:nChannels-1)*offset_scale;
            yticks_labels = cell(1, nChannels);
            if ~isempty(app.emg_chanlocs) && length(app.emg_chanlocs) == nChannels
                 for i=1:nChannels, yticks_labels{i} = app.emg_chanlocs{nChannels-i+1}; end
            else
                 for i=1:nChannels, yticks_labels{i} = sprintf('EMG Ch %d', nChannels-i+1); end
            end
            set(app.EMGAxes, 'YTick', sort(yticks_pos), 'YTickLabel', yticks_labels);

            xlabel(app.EMGAxes, 'Time (s)');
            ylabel(app.EMGAxes, 'Channels');
            title(app.EMGAxes, 'EMG Time Domain Signals');
            axis(app.EMGAxes, 'tight');
            if ~isempty(app.ECoGAxes.Children) 
                 app.linkTimeAxes();
            end
        end

        % Function to link X axes of ECoG and EMG plots
        function linkTimeAxes(app)
            if ~isempty(app.ECoGAxes.Children) && ~isempty(app.EMGAxes.Children)
                linkaxes([app.ECoGAxes, app.EMGAxes], 'x');
            end
        end

        % Button pushed function: AnalyzeChannelButton
        function AnalyzeChannelButtonPushed(app, event)
            if isempty(app.ecog_data) || isempty(app.ChannelListBox.Value) || isempty(app.ecog_srate)
                uialert(app.UIFigure, 'Please load ECoG data and select one or more channels.', 'Warning', 'Interpreter', 'none');
                return;
            end

            selectedChannelNames = app.ChannelListBox.Value;
            if ~iscell(selectedChannelNames), selectedChannelNames = {selectedChannelNames}; end
            if isempty(selectedChannelNames) || isempty(selectedChannelNames{1})
                 uialert(app.UIFigure, 'No channels selected for analysis.', 'Warning', 'Interpreter', 'none');
                return;
            end

            numSelectedChannels = length(selectedChannelNames);
            fprintf('AnalyzeChannelButtonPushed: Number of selected channels: %d\n', numSelectedChannels);
            expectedRowHeight = 250; % px per plot
            totalPaddingAndSpacing = (numSelectedChannels + 1) * 10; % Approx.

            % --- 配置 SpectrogramGridContainer (可滚动的父grid) ---
            delete(app.SpectrogramGridContainer.Children); % 清除旧的uiaxes
            drawnow;
            % 直接在这个可滚动的uigridlayout上设置多行
            app.SpectrogramGridContainer.RowHeight = repmat({expectedRowHeight}, 1, numSelectedChannels);
            app.SpectrogramGridContainer.ColumnWidth = {'1x'}; % 保持单列填充宽度
            app.SpectrogramGridContainer.Padding = [10 10 10 10];
            app.SpectrogramGridContainer.RowSpacing = 10;
            drawnow;
            % 背景色已在createComponents中设置 (淡蓝色)
            fprintf('SpectrogramGridContainer On-Screen Position: [%.1f %.1f %.1f %.1f]\n', app.SpectrogramGridContainer.Position);
            fprintf('SpectrogramGridContainer Expected Content Height (approx): %.1f\n', numSelectedChannels * expectedRowHeight + totalPaddingAndSpacing);


            % --- 配置 PSDGridContainer (可滚动的父grid) ---
            delete(app.PSDGridContainer.Children);
            drawnow;
            app.PSDGridContainer.RowHeight = repmat({expectedRowHeight}, 1, numSelectedChannels);
            app.PSDGridContainer.ColumnWidth = {'1x'};
            app.PSDGridContainer.Padding = [10 10 10 10];
            app.PSDGridContainer.RowSpacing = 10;
            drawnow;
            % 背景色已在createComponents中设置 (淡绿色)
            fprintf('PSDGridContainer On-Screen Position: [%.1f %.1f %.1f %.1f]\n', app.PSDGridContainer.Position);
            fprintf('PSDGridContainer Expected Content Height (approx): %.1f\n', numSelectedChannels * expectedRowHeight + totalPaddingAndSpacing);


            % --- 循环创建坐标轴和绘图 ---
            for i = 1:numSelectedChannels
                currentChannelName = selectedChannelNames{i};
                channelIndex = find(strcmp(app.ecog_chanlocs, currentChannelName), 1);

                if isempty(channelIndex)
                     uialert(app.UIFigure, ['Channel "',currentChannelName,'" not found. Skipping.'], 'Warning', 'Interpreter', 'none');
                     continue;
                end
                channelData = app.ecog_data(channelIndex, :);

                window_duration_sec = 1;
                window_samples = round(window_duration_sec * app.ecog_srate);
                if window_samples < 2, window_samples = min(length(channelData), 256); end
                window_vec = hamming(min(window_samples, length(channelData)));
                noverlap_percentage = 0.5;
                noverlap = round(length(window_vec) * noverlap_percentage);
                nfft = max(256, 2^nextpow2(length(window_vec)));

                if length(channelData) < length(window_vec)
                    % 为 Spectrogram 创建占位
                    axSpec = uiaxes(app.SpectrogramGridContainer); % 父级是可滚动的GridContainer
                    axSpec.Layout.Row = i; axSpec.Layout.Column = 1;
                    title(axSpec, ['Spectrogram: ', currentChannelName, ' (Data too short)']);
                    text(axSpec, 0.5, 0.5, 'Data too short', 'HorizontalAlignment', 'center');
                    % disableDefaultInteractivity(axSpec);

                    % 为 PSD 创建占位
                    axPSD = uiaxes(app.PSDGridContainer); % 父级是可滚动的GridContainer
                    axPSD.Layout.Row = i; axPSD.Layout.Column = 1;
                    title(axPSD, ['PSD: ', currentChannelName, ' (Data too short)']);
                    text(axPSD, 0.5, 0.5, 'Data too short', 'HorizontalAlignment', 'center');
                    % disableDefaultInteractivity(axPSD);
                    continue;
                end

                % --- Time-Frequency Plot (Spectrogram) - 手动绘制 ---
                axSpec = uiaxes(app.SpectrogramGridContainer); % 父级是可滚动的GridContainer
                axSpec.Layout.Row = i; axSpec.Layout.Column = 1;

                [S, F_spec, T_spec] = spectrogram(channelData, window_vec, noverlap, nfft, app.ecog_srate);
                
                S_db = 10*log10(abs(S));
                S_db(isinf(S_db) & S_db < 0) = NaN; % Handle -Inf, imagesc can render NaN transparently or as a set color

                imagesc(axSpec, T_spec, F_spec, 10*log10(abs(S))); % 使用imagesc绘制
                axis(axSpec, 'xy'); % 设置坐标轴方向，使低频在下，时间从左到右
                axis(axSpec, 'tight'); %使图像内容填充坐标轴
                % colormap(axSpec, 'jet'); % 或者使用parula等其他颜色图

                title(axSpec, ['Spectrogram: ', currentChannelName]);
                xlabel(axSpec, 'Time (s)');
                ylabel(axSpec, 'Frequency (Hz)');

                if any(isfinite(S_db(:))) % Only add colorbar and set Clim if data is valid
                    valid_clim_data = S_db(isfinite(S_db(:)));
                    if ~isempty(valid_clim_data)
                        c_limits = [min(valid_clim_data), max(valid_clim_data)];
                        if c_limits(1) < c_limits(2)
                            clim(axSpec, c_limits);
                        elseif c_limits(1) == c_limits(2)
                            clim(axSpec, c_limits(1) + [-0.5 0.5]); % Handle flat data
                        end
                    end
                    try colorbar(axSpec,'Location','eastoutside'); catch; end
                end

                % enableDefaultInteractivity(axSpec);

                % --- Power Spectral Density (PSD) ---
                axPSD = uiaxes(app.PSDGridContainer); % 父级是可滚动的GridContainer
                axPSD.Layout.Row = i; axPSD.Layout.Column = 1;
                [pxx, f_psd] = pwelch(channelData, window_vec, noverlap, nfft, app.ecog_srate);
                plot(axPSD, f_psd, 10*log10(pxx));
                title(axPSD, ['PSD: ', currentChannelName]);
                xlabel(axPSD, 'Frequency (Hz)'); ylabel(axPSD, 'Power/Frequency (dB/Hz)');
                grid(axPSD, 'on'); axis(axPSD, 'tight');
                enableDefaultInteractivity(axPSD);
            end

            drawnow;
            app.DisplayTabGroup.SelectedTab = app.TimeFrequencyTab;
            uialert(app.UIFigure, ['Analysis complete for ', num2str(numSelectedChannels), ' channel(s).'], 'Success', 'Interpreter', 'none');
        end
        
        % --- Placeholder Callbacks for Future Features ---
        function FilterTypeDropDownValueChanged(app, event)
            filterType = app.FilterTypeDropDown.Value;
            switch lower(filterType)
                case {'lowpass', 'highpass'}
                    app.CutoffFreq1Label.Text = 'Cutoff (Hz):';
                    app.CutoffFreq2EditField.Visible = 'off';
                    app.CutoffFreq2Label.Visible = 'off';
                case {'bandpass', 'bandstop'}
                    app.CutoffFreq1Label.Text = 'Freq1 (Hz):';
                    app.CutoffFreq2EditField.Visible = 'on';
                    app.CutoffFreq2Label.Visible = 'on';
                    app.CutoffFreq2Label.Text = 'Freq2 (Hz):';
                otherwise % None
                    app.CutoffFreq1Label.Text = 'Cutoff1 (Hz):';
                    app.CutoffFreq2EditField.Visible = 'off';
                    app.CutoffFreq2Label.Visible = 'off';
            end
        end

        function ApplyFilterButtonPushed(app, event)
            uialert(app.UIFigure, 'Filter function not yet implemented.', 'Info');
            % Future: Implement filtering logic here
            % 1. Read parameters from UI
            % 2. Design filter (e.g., using designfilt or butter)
            % 3. Apply filter (filtfilt) to app.ecog_data_raw -> app.ecog_data_filtered
            % 4. Update app.ecog_data (if CAR not applied, ecog_data = ecog_data_filtered)
            % 5. If CAR is applied, re-apply CAR to the newly filtered data.
            % 6. app.isFilterApplied = 'on';
            % 7. app.updateProcessingStatusLabel();
            % 8. app.plotTimeDomainECoG();
        end

        function ApplyCARButtonPushed(app, event)
             uialert(app.UIFigure, 'CAR function not yet implemented.', 'Info');
            % Future: Implement CAR logic here
            % 1. Determine base data (app.ecog_data_filtered or app.ecog_data_raw)
            % 2. Calculate CAR signal: mean_signal = mean(base_data, 1);
            % 3. Subtract CAR: app.ecog_data = base_data - mean_signal;
            % 4. app.isCARApplied = 'on'; (or toggle)
            % 5. app.updateProcessingStatusLabel();
            % 6. app.plotTimeDomainECoG();
        end
        
        function ResetProcessingButtonPushed(app, event)
            if isempty(app.ecog_data_raw)
                uialert(app.UIFigure, 'No ECoG data loaded to reset.', 'Info');
                return;
            end
            app.ecog_data_filtered = app.ecog_data_raw;
            app.ecog_data = app.ecog_data_raw;
            app.isFilterApplied = 'off';
            app.isCARApplied = 'off';
            
            % Reset filter UI
            app.FilterTypeDropDown.Value = 'None';
            app.CutoffFreq1EditField.Value = 0;
            app.CutoffFreq2EditField.Value = 0;
            app.FilterOrderEditField.Value = 4; % Default order
            app.FilterTypeDropDownValueChanged(app,event); % Update visibility
            
            app.updateProcessingStatusLabel();
            app.plotTimeDomainECoG(); % Re-plot with raw data
            uialert(app.UIFigure, 'ECoG processing reset to raw data.', 'Success');
        end
        
        function updateProcessingStatusLabel(app)
            status_parts = {};
            if strcmp(app.isFilterApplied, 'on')
                params = app.lastFilterParams; % Assuming this gets populated
                filter_str = sprintf('Filtered: %s', params.Type);
                if isfield(params, 'Fc1')
                    filter_str = [filter_str, sprintf(' %.1fHz', params.Fc1)];
                end
                if isfield(params, 'Fc2') && params.Fc2 > 0
                     filter_str = [filter_str, sprintf('-%.1fHz', params.Fc2)];
                end
                 if isfield(params, 'Order')
                     filter_str = [filter_str, sprintf(' O%d', params.Order)];
                end
                status_parts{end+1} = filter_str;
            end
            if strcmp(app.isCARApplied, 'on')
                status_parts{end+1} = 'CAR Applied';
            end
            
            if isempty(status_parts)
                app.ProcessingStatusLabel.Text = 'Status: Raw Data';
            else
                app.ProcessingStatusLabel.Text = ['Status: ', strjoin(status_parts, '; ')];
            end
            app.ProcessingStatusLabel.FontColor = [0 0.4470 0.7410]; % Blue
        end


    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1200 750]; % Increased size
            app.UIFigure.Name = 'ECoG/EMG Analysis Tool v2';

            % Main GridLayout
            app.GridLayout = uigridlayout(app.UIFigure);
            app.GridLayout.ColumnWidth = {300, '1x'}; % Control panel width, Display area
            app.GridLayout.RowHeight = {'1x'};

            % --- Create LeftPanel (Combined Controls) ---
            LeftPanel = uipanel(app.GridLayout);
            LeftPanel.Layout.Row = 1; LeftPanel.Layout.Column = 1;
            LeftPanel.Title = 'Controls & Processing';
            LeftPanelLayout = uigridlayout(LeftPanel);
            LeftPanelLayout.RowHeight = {'fit', 'fit', 'fit'}; % File Ops, Analysis, Processing
            LeftPanelLayout.ColumnWidth = {'1x'};

            % --- File Operations Panel ---
            app.ControlPanel = uipanel(LeftPanelLayout);
            app.ControlPanel.Layout.Row = 1; app.ControlPanel.Layout.Column = 1;
            app.ControlPanel.Title = 'File Operations & Channel Selection';
            controlPanelLayout = uigridlayout(app.ControlPanel);
            controlPanelLayout.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', '1x', 'fit'}; 
            controlPanelLayout.ColumnWidth = {'1x'};

            app.LoadECoGButton = uibutton(controlPanelLayout, 'push', 'Text', 'Load ECoG (EDF)', 'ButtonPushedFcn', createCallbackFcn(app, @LoadECoGButtonPushed, true));
            app.LoadECoGButton.Layout.Row = 1; app.LoadECoGButton.Layout.Column = 1;

            app.ECoGFilePathLabel = uilabel(controlPanelLayout, 'Text', 'ECoG: No file loaded', 'WordWrap', 'on');
            app.ECoGFilePathLabel.Layout.Row = 2; app.ECoGFilePathLabel.Layout.Column = 1;

            app.LoadEMGButton = uibutton(controlPanelLayout, 'push', 'Text', 'Load EMG (EDF)', 'ButtonPushedFcn', createCallbackFcn(app, @LoadEMGButtonPushed, true));
            app.LoadEMGButton.Layout.Row = 3; app.LoadEMGButton.Layout.Column = 1;

            app.EMGFilePathLabel = uilabel(controlPanelLayout, 'Text', 'EMG: No file loaded', 'WordWrap', 'on');
            app.EMGFilePathLabel.Layout.Row = 4; app.EMGFilePathLabel.Layout.Column = 1;
            
            app.ChannelListBoxLabel = uilabel(controlPanelLayout, 'Text', 'Select ECoG Channel(s) for Analysis:', 'VerticalAlignment', 'bottom');
            app.ChannelListBoxLabel.Layout.Row = 5; app.ChannelListBoxLabel.Layout.Column = 1;

            app.ChannelListBox = uilistbox(controlPanelLayout, 'Items', {}, 'Multiselect', 'on'); % Enable Multiselect
            app.ChannelListBox.Layout.Row = 6; app.ChannelListBox.Layout.Column = 1;

            app.AnalyzeChannelButton = uibutton(controlPanelLayout, 'push', 'Text', 'Analyze Selected Channel(s)', 'ButtonPushedFcn', createCallbackFcn(app, @AnalyzeChannelButtonPushed, true));
            app.AnalyzeChannelButton.Layout.Row = 7; app.AnalyzeChannelButton.Layout.Column = 1;

            % --- Processing Panel ---
            app.ProcessingPanel = uipanel(LeftPanelLayout);
            app.ProcessingPanel.Layout.Row = 2; app.ProcessingPanel.Layout.Column = 1;
            app.ProcessingPanel.Title = 'Signal Processing';
            processingLayout = uigridlayout(app.ProcessingPanel);
            processingLayout.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'};
            processingLayout.ColumnWidth = {'fit', '1x'}; % Labels and Controls

            app.FilterTypeDropDownLabel = uilabel(processingLayout, 'Text', 'Filter Type:');
            app.FilterTypeDropDownLabel.Layout.Row = 1; app.FilterTypeDropDownLabel.Layout.Column = 1;
            app.FilterTypeDropDown = uidropdown(processingLayout, 'Items', {'None', 'Lowpass', 'Highpass', 'Bandpass', 'Bandstop'}, 'Value', 'None', ...
                                                'ValueChangedFcn', createCallbackFcn(app, @FilterTypeDropDownValueChanged, true));
            app.FilterTypeDropDown.Layout.Row = 1; app.FilterTypeDropDown.Layout.Column = 2;

            app.CutoffFreq1Label = uilabel(processingLayout, 'Text', 'Cutoff1 (Hz):');
            app.CutoffFreq1Label.Layout.Row = 2; app.CutoffFreq1Label.Layout.Column = 1;
            app.CutoffFreq1EditField = uieditfield(processingLayout, 'numeric', 'Value', 0);
            app.CutoffFreq1EditField.Layout.Row = 2; app.CutoffFreq1EditField.Layout.Column = 2;

            app.CutoffFreq2Label = uilabel(processingLayout, 'Text', 'Cutoff2 (Hz):', 'Visible', 'off');
            app.CutoffFreq2Label.Layout.Row = 3; app.CutoffFreq2Label.Layout.Column = 1;
            app.CutoffFreq2EditField = uieditfield(processingLayout, 'numeric', 'Value', 0, 'Visible', 'off');
            app.CutoffFreq2EditField.Layout.Row = 3; app.CutoffFreq2EditField.Layout.Column = 2;
            
            app.FilterOrderLabel = uilabel(processingLayout, 'Text', 'Order:');
            app.FilterOrderLabel.Layout.Row = 4; app.FilterOrderLabel.Layout.Column = 1;
            app.FilterOrderEditField = uieditfield(processingLayout, 'numeric', 'Value', 4, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
            app.FilterOrderEditField.Layout.Row = 4; app.FilterOrderEditField.Layout.Column = 2;

            app.ApplyFilterButton = uibutton(processingLayout, 'push', 'Text', 'Apply Filter', 'ButtonPushedFcn', createCallbackFcn(app, @ApplyFilterButtonPushed, true));
            app.ApplyFilterButton.Layout.Row = 5; 
            app.ApplyFilterButton.Layout.Column = [1, 2]; % 修改这里

            app.ApplyCARButton = uibutton(processingLayout, 'push', 'Text', 'Apply Common Average Ref.', 'ButtonPushedFcn', createCallbackFcn(app, @ApplyCARButtonPushed, true));
            app.ApplyCARButton.Layout.Row = 6; 
            app.ApplyCARButton.Layout.Column = [1, 2]; % 修改这里
            
            app.ResetProcessingButton = uibutton(processingLayout, 'push', 'Text', 'Reset to Raw Data', 'ButtonPushedFcn', createCallbackFcn(app, @ResetProcessingButtonPushed, true));
            app.ResetProcessingButton.Layout.Row = 7; 
            app.ResetProcessingButton.Layout.Column = [1, 2]; % 修改这里
            
            app.ProcessingStatusLabel = uilabel(processingLayout, 'Text', 'Status: Raw Data', 'FontWeight', 'bold');
            app.ProcessingStatusLabel.Layout.Row = 8; 
            app.ProcessingStatusLabel.Layout.Column = [1, 2]; % 修改这里

            % --- Create DisplayTabGroup (Right) ---
            app.DisplayTabGroup = uitabgroup(app.GridLayout);
            app.DisplayTabGroup.Layout.Row = 1;
            app.DisplayTabGroup.Layout.Column = 2;

            % Time Domain Tab
            app.TimeDomainTab = uitab(app.DisplayTabGroup, 'Title', 'Time Domain');
            app.TimeDomainGridLayout = uigridlayout(app.TimeDomainTab, [2,1], 'RowHeight', {'1x', '1x'}, 'ColumnWidth', {'1x'});

            app.ECoGAxes = uiaxes(app.TimeDomainGridLayout);
            app.ECoGAxes.Layout.Row = 1; app.ECoGAxes.Layout.Column = 1;
            title(app.ECoGAxes, 'ECoG Signals'); xlabel(app.ECoGAxes, 'Time (s)'); ylabel(app.ECoGAxes, 'Channels');

            app.EMGAxes = uiaxes(app.TimeDomainGridLayout);
            app.EMGAxes.Layout.Row = 2; app.EMGAxes.Layout.Column = 1;
            title(app.EMGAxes, 'EMG Signals'); xlabel(app.EMGAxes, 'Time (s)'); ylabel(app.EMGAxes, 'Channels');

            % --- Time-Frequency Tab ---
            app.TimeFrequencyTab = uitab(app.DisplayTabGroup, 'Title', 'Time-Frequency');
            % 用一个可滚动的uigridlayout替换uipanel
            app.SpectrogramGridContainer = uigridlayout(app.TimeFrequencyTab, [1,1], ... % 1行1列，将填充父Tab
                'Padding', [0 0 0 0], ... % 这个父grid不需要padding
                'Scrollable', 'on', ...    % 使这个父grid可滚动
                'BackgroundColor', [0.9 0.95 1]); % 淡蓝色背景 (父grid的背景)

            % --- Power Spectrum Tab ---
            app.PowerSpectrumTab = uitab(app.DisplayTabGroup, 'Title', 'Power Spectrum');
            % 用一个可滚动的uigridlayout替换uipanel
            app.PSDGridContainer = uigridlayout(app.PowerSpectrumTab, [1,1], ...
                'Padding', [0 0 0 0], ...
                'Scrollable', 'on', ...
                'BackgroundColor', [0.95 1 0.95]); % 淡绿色背景 (父grid的背景)
            
            % Initialize Filter UI state
            app.FilterTypeDropDownValueChanged([]);


            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = ECoGAnalysisApp()
            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)
            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end