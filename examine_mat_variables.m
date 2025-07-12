function examine_mat_variables()
% examine_mat_variables 帮助用户检视 .mat 文件中的变量名。
%
%   此脚本会打开一个文件选择对话框，允许用户选择一个或多个 .mat 文件，
%   然后列出每个文件中包含的所有变量名称。

    fprintf('--------------------------------------------------\n');
    fprintf('.mat 文件变量名检视工具\n');
    fprintf('--------------------------------------------------\n');

    % 打开文件选择对话框，允许选择多个 .mat 文件
    [file_names, folder_path] = uigetfile('*.mat', '选择一个或多个 .mat 文件', 'MultiSelect', 'on');

    % 检查用户是否取消了选择
    if isequal(file_names, 0)
        fprintf('用户取消了文件选择。脚本结束。\n');
        return;
    end

    % 如果只选择了一个文件，uigetfile 返回的是字符串，需要转换为 cell 数组
    if ischar(file_names)
        file_names = {file_names};
    end

    % 遍历所有选定的文件
    for i = 1:length(file_names)
        current_file_name = file_names{i};
        full_file_path = fullfile(folder_path, current_file_name);
        
        fprintf('\n--- 文件: %s ---\n', current_file_name);
        
        try
            % 使用 whos('-file', filename) 获取文件中所有变量的信息
            % 这是一个高效的方法，无需将整个文件加载到内存中
            var_info = whos('-file', full_file_path);
            
            if isempty(var_info)
                fprintf('  文件中没有找到任何变量。\n');
            else
                fprintf('  文件中包含以下变量：\n');
                for j = 1:length(var_info)
                    fprintf('    - %s (大小: %s, 类型: %s)\n', var_info(j).name, mat2str(var_info(j).size), var_info(j).class);
                end
            end
        catch ME
            fprintf('  加载文件 %s 时发生错误: %s\n', current_file_name, ME.message);
        end
    end

    fprintf('\n--------------------------------------------------\n');
    fprintf('检视完成。\n');
    fprintf('--------------------------------------------------\n');

end