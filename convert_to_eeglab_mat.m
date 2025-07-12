function convert_to_eeglab_mat(input_mat_file, output_eeglab_mat_file)
% convert_to_eeglab_mat Converts a custom .mat file to EEGLAB-compatible .mat format.
%
%   input_mat_file: Path to your preprocessed .mat file
%                   (e.g., 'Temp_250704_140458_preprocessed_preprocessed.mat')
%   output_eeglab_mat_file: Desired path for the output EEGLAB .mat file
%                          (e.g., 'my_eeglab_data.set')

    if nargin < 2
        error('Please provide input and output file paths.');
    end

    fprintf('Loading your preprocessed data from: %s\n', input_mat_file);
    try
        loaded_data = load(input_mat_file);
    catch ME
        error('Error loading input .mat file: %s', ME.message);
    end

    % 1. Extract your ECoG data and sampling rate
    if isfield(loaded_data, 'concatenated_ecog')
        EEG.data = loaded_data.concatenated_ecog;
        fprintf('Found ECoG data in ''concatenated_ecog''. Data dimensions: %s\n', mat2str(size(EEG.data)));
    else
        error('''concatenated_ecog'' variable not found in the input .mat file.');
    end

    if isfield(loaded_data, 'target_sampling_rate')
        EEG.srate = loaded_data.target_sampling_rate(1); % Ensure it's a scalar
        fprintf('Found sampling rate in ''target_sampling_rate'': %g Hz\n', EEG.srate);
    else
        error('''target_sampling_rate'' variable not found in the input .mat file.');
    end

    % 2. Populate essential EEGLAB EEG struct fields
    EEG.nbchan = size(EEG.data, 1);     % Number of channels
    EEG.pnts = size(EEG.data, 2);       % Number of data points per channel
    EEG.trials = 1;                     % Assuming continuous data, so 1 trial
    EEG.xmin = 0;                       % Start time of the data (in seconds)
    EEG.xmax = (EEG.pnts - 1) / EEG.srate; % End time of the data (in seconds)
    EEG.times = (0:EEG.pnts-1) / EEG.srate; % Time vector (optional but good to have)
    EEG.event = [];                     % Initialize empty events (you can add later in EEGLAB)
    EEG.chanlocs = [];                  % Initialize empty channel locations (important for plotting in EEGLAB)
    EEG.setname = 'My_ECoG_Data';       % Set name
    EEG.filename = output_eeglab_mat_file;
    EEG.filepath = fileparts(output_eeglab_mat_file);
    EEG.subject = 'Rat';                % Example subject
    EEG.group = '';                     % Example group
    EEG.condition = '';                 % Example condition
    EEG.epoch = [];                     % For epoched data
    EEG.icaweights = [];                % For ICA results
    EEG.icasphere = [];                 % For ICA results
    EEG.etc = [];                       % For miscellaneous information
    
    % 3. Transpose data if necessary (EEGLAB prefers channels x timepoints)
    % Your data is [128 381031], which is channels x timepoints, so usually no transpose needed.
    % But if for some reason it's (timepoints x channels), it should be transposed.
    if size(EEG.data,1) > size(EEG.data,2) && size(EEG.data,2) < 200 % Heuristic for timepoints x channels
        EEG.data = EEG.data';
        fprintf('Data transposed to (channels x timepoints) for EEGLAB compatibility.\n');
    end

    % 4. Save the EEG struct to a .mat file
    % EEGLAB's pop_saveset typically saves with a .set extension, but it's fundamentally a .mat file.
    % We'll save it directly as a .mat file for now. You can then load it into EEGLAB.
    try
        save(output_eeglab_mat_file, 'EEG', '-v7.3'); % Use -v7.3 for large files
        fprintf('Successfully converted and saved to EEGLAB-compatible .mat file: %s\n', output_eeglab_mat_file);
        fprintf('You can now open EEGLAB and load this file (File > Load existing dataset).\n');
    catch ME
        error('Error saving EEGLAB .mat file: %s', ME.message);
    end
end