%% run_logdb.m  —  Main entrypoint for the log event database pipeline.
%
%  Edit the two paths below, then run this script.
%  On first run it builds the full database; subsequent runs append new events only.
%
%  After building, launch the viewer:
%    v = logdb.Viewer.fromFile(cfg.DatabaseMatPath);
%    v.launch();

%% Configuration
cfg = logdb.Config( ...
    'RootRawDir',   'D:\MATLAB\LM\Archive\test_inputs\TestRoot', ...        % <-- set to your raw data root
    'ProcessedDir', 'D:\MATLAB\LM\Archive\Output Dir', ...  % <-- set to your output directory
    'Evaluators',   { logdb.eval.ExampleEvaluator() } ...
);

%% Build / Update
runner = logdb.PipelineRunner(cfg);
db     = runner.runBuild();

%% Launch Viewer (optional — comment out for headless runs)
% v = logdb.Viewer(db);
% v.launch();                            % no groups

%% Launch Viewer with grouped points of interest
%  Specify {EventID, EntityID, GroupLabel} for points you want colored.
%  Points not in any group are plotted normally (blue-to-red by distance).
%  Use the dropdown at the top of the figure to emphasize one group.
%
groups = { ...                                        % <-- EDIT
    "04_03_10_2024_1_c2",  1,  "Batch A", "anomaly"; ...         % event, entity, group
    "04_03_10_2024_1_c2",  2,  "Batch B", ""; ...  
    "03_02_01_2024_1_a1",  1,  "Batch C", "anomaly"; ...
    "03_02_01_2024_1_a1",  2,  "Batch A", ""; ...
};
v = logdb.Viewer(db);
v.launch(groups);

%% Launch GroupViewer (one group per subplot)
%  Same groups list — subplot 1 shows all data, subplots 2-4 show
%  one group each with everything else greyed out.
%  Optional 4th column "anomaly" adds a fixed-size red ring overlay.
%
groups = { ...                                        % <-- EDIT
    "04_03_10_2024_1_c2",  1,  "Batch A", "anomaly"; ...         % event, entity, group
    "04_03_10_2024_1_c2",  2,  "Batch B", ""; ...  
    "03_02_01_2024_1_a1",  1,  "Batch C", "anomaly"; ...
};

gv = logdb.GroupViewer(db);
gv.launch(groups);
