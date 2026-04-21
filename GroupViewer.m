classdef GroupViewer < handle
    % logdb.GroupViewer  One-group-per-subplot viewer with anomaly overlay.
    %
    %   Subplot layout:
    %     1 (top-left)  : All data, normal coloring
    %     2 (top-right) : Group 1 highlighted, rest greyed out
    %     3 (bot-left)  : Group 2 highlighted, rest greyed out
    %     4 (bot-right) : Group 3 highlighted, rest greyed out
    %
    %   All 4 subplots use the same rectangle bounding box.
    %   Points tagged as "anomaly" get a red ring overlay on all subplots.
    %   The red rings use plot() markers (fixed screen size — won't grow
    %   when you zoom out).
    %
    %   Usage:
    %     groups = { ...
    %         "01_03_15_2024_1_a1",  3,  "Batch A"; ...
    %         "02_01_16_2024_2_b1",  1,  "Batch A", "anomaly"; ...
    %         "03_02_01_2024_1_a1",  2,  "Batch B", "anomaly"; ...
    %         "04_03_10_2024_1_c2",  1,  "Batch C"; ...
    %     };
    %     gv = logdb.GroupViewer(db);
    %     gv.launch(groups);
    %
    %   The 4th column is optional.  If present and set to "anomaly",
    %   that point gets a red ring on every subplot it appears in.
    %
    %   Search for "<-- EDIT" to find every configurable line.

    properties (Constant)

        TITLE  = "Group Comparison"          % <-- EDIT  figure window title

        XLABEL = "X Label"                   % <-- EDIT  x-axis label (all subplots)
        YLABEL = "Y Label"                   % <-- EDIT  y-axis label (all subplots)
        XCOL   = "Metric_X"                  % <-- EDIT  PointTable column for X
        YCOL   = "Metric_Y"                  % <-- EDIT  PointTable column for Y

        % Rectangle bounds [Xmin, Xmax, Ymin, Ymax]
        RECT = [-10, 10, -10, 10]            % <-- EDIT  bounding rectangle
        SHOW_BOUNDS = true                   % <-- EDIT  false to hide

        % Group colors
        GROUP_COLORS = [ ...                 % <-- EDIT
            0.10 0.60 0.10; ...   % group 1: green
            0.10 0.10 0.90; ...   % group 2: blue
            0.95 0.60 0.05; ...   % group 3: orange
        ]

        % Anomaly ring appearance
        ANOMALY_COLOR     = [1 0 0]          % <-- EDIT  red
        ANOMALY_MARKER_SZ = 10               % <-- EDIT  marker size in points (fixed)
        ANOMALY_LINE_WD   = 2.0              % <-- EDIT  ring line width
    end

    properties (Access = private)
        DB
        Fig
    end

    methods
        function obj = GroupViewer(db)
            arguments
                db logdb.Database
            end
            obj.DB = db;
        end

        function launch(obj, groups)
            % LAUNCH  Create 2x2 figure: all data + one group per subplot.
            %
            %   gv.launch(groups)
            %   groups is Nx3 or Nx4 cell:
            %     {EventID, EntityID, GroupLabel; ...}           no anomalies
            %     {EventID, EntityID, GroupLabel, "anomaly"; ...} with anomalies
            %   Rows without a 4th column (or with empty 4th) are not anomalies.

            pts  = obj.DB.getPoints();
            evts = obj.DB.getEvents();
            assert(~isempty(pts) && height(pts) > 0, ...
                'logdb:GroupViewer:noData', 'PointTable is empty.');

            % --- Parse groups and anomaly tags ---
            groupLabels = repmat("", height(pts), 1);
            anomalyMask = false(height(pts), 1);

            if nargin >= 2 && ~isempty(groups) && iscell(groups)
                grpEvents   = string(groups(:,1));
                grpEntities = cell2mat(groups(:,2));
                grpLabels   = string(groups(:,3));

                % Parse optional 4th column (anomaly tag)
                nCols = size(groups, 2);
                if nCols >= 4
                    anomalyTags = string(groups(:,4));
                    % Handle empty cells that become <missing>
                    anomalyTags(ismissing(anomalyTags)) = "";
                else
                    anomalyTags = repmat("", size(groups,1), 1);
                end

                % Determine which column to match entity IDs against
                if ismember('EntityID', pts.Properties.VariableNames)
                    entityCol = pts.EntityID;
                elseif ismember('PointID', pts.Properties.VariableNames)
                    entityCol = pts.PointID;
                else
                    entityCol = [];
                end

                if ~isempty(entityCol)
                    for g = 1:numel(grpEvents)
                        match = pts.EventID == grpEvents(g) & ...
                                entityCol == grpEntities(g);
                        groupLabels(match) = grpLabels(g);
                        if lower(anomalyTags(g)) == "anomaly"
                            anomalyMask(match) = true;
                        end
                    end
                end
            end

            uniqueGroups = unique(groupLabels(groupLabels ~= ""), 'stable');
            nGroups = min(numel(uniqueGroups), 3);

            % --- Precompute shared data ---
            rect  = obj.RECT;
            xCol  = char(obj.XCOL);
            yCol  = char(obj.YCOL);
            xData = pts.(xCol);
            yData = pts.(yCol);

            if obj.SHOW_BOUNDS
                inBox = xData >= rect(1) & xData <= rect(2) & ...
                        yData >= rect(3) & yData <= rect(4);
            else
                inBox = true(size(xData));
            end

            anomalyStyle = struct( ...
                'Color',     obj.ANOMALY_COLOR, ...
                'MarkerSize', obj.ANOMALY_MARKER_SZ, ...
                'LineWidth', obj.ANOMALY_LINE_WD);

            % --- Figure ---
            obj.Fig = figure('Name', char(obj.TITLE), ...
                'Position', [50 50 1400 900], 'Color', 'w');

            % === Subplot 1: All data ===
            ax1 = subplot(2, 2, 1);
            plotAll(ax1, pts, evts, xCol, yCol, xData, yData, inBox, ...
                rect, obj.SHOW_BOUNDS, groupLabels, anomalyMask, anomalyStyle);
            title(ax1, 'All Data', 'Interpreter', 'none');
            xlabel(ax1, obj.XLABEL, 'Interpreter', 'none');
            ylabel(ax1, obj.YLABEL, 'Interpreter', 'none');

            % === Subplots 2-4: One group each ===
            for g = 1:nGroups
                ax = subplot(2, 2, g + 1);
                gName  = uniqueGroups(g);
                gColor = obj.GROUP_COLORS(g, :);
                gMask  = groupLabels == gName;

                plotGroupEmphasis(ax, pts, evts, xCol, yCol, xData, yData, ...
                    inBox, rect, obj.SHOW_BOUNDS, gMask, gColor, char(gName), ...
                    anomalyMask, anomalyStyle);
                title(ax, char(gName), 'Interpreter', 'none');
                xlabel(ax, obj.XLABEL, 'Interpreter', 'none');
                ylabel(ax, obj.YLABEL, 'Interpreter', 'none');
            end

            % Blank out unused subplots
            for g = (nGroups+1):3
                ax = subplot(2, 2, g + 1);
                set(ax, 'Visible', 'off');
            end

            % --- Data cursor ---
            dcm = datacursormode(obj.Fig);
            dcm.Enable = 'on';
            dcm.UpdateFcn = @groupDataCursorFcn;
        end
    end

    methods (Static)
        function v = fromFile(matPath)
            db = logdb.Database();
            db.load(matPath);
            v = logdb.GroupViewer(db);
        end
    end
end

% =========================================================================
%  Anomaly overlay — uses plot() so markers are fixed screen size
% =========================================================================
function drawAnomalies(ax, xData, yData, anomalyMask, style)
    if any(anomalyMask)
        plot(ax, xData(anomalyMask), yData(anomalyMask), 'o', ...
            'Color', style.Color, ...
            'MarkerSize', style.MarkerSize, ...
            'LineWidth', style.LineWidth, ...
            'HandleVisibility', 'off');  % exclude from legend
    end
end

% =========================================================================
%  Subplot 1: All data with normal coloring
% =========================================================================
function plotAll(ax, pts, evts, xCol, yCol, xData, yData, inBox, ...
        rect, showBounds, groupLabels, anomalyMask, anomalyStyle)

    dist = sqrt(xData.^2 + yData.^2);
    nC = 256;
    colormap(ax, [linspace(0,1,nC)', zeros(nC,1), linspace(1,0,nC)']);

    % In-bounds
    if any(inBox)
        scatter(ax, xData(inBox), yData(inBox), 36, dist(inBox), ...
            'filled', 'MarkerFaceAlpha', 0.7);
    end
    hold(ax, 'on');

    % Out-of-bounds: x markers
    oob = ~inBox;
    if any(oob)
        scatter(ax, xData(oob), yData(oob), 36, dist(oob), ...
            'Marker', 'x', 'LineWidth', 1.5);
    end

    % Anomaly rings (drawn on top, fixed size)
    drawAnomalies(ax, xData, yData, anomalyMask, anomalyStyle);

    drawRect(ax, rect, showBounds);
    hold(ax, 'off');
    grid(ax, 'on');
    if any(isfinite(dist)); caxis(ax, [0 max(dist(isfinite(dist)))]); end
    colorbar(ax);

    ax.UserData.pts         = pts;
    ax.UserData.evts        = evts;
    ax.UserData.xCol        = xCol;
    ax.UserData.yCol        = yCol;
    ax.UserData.groupLabels = groupLabels;
    ax.UserData.anomalyMask = anomalyMask;
end

% =========================================================================
%  Subplots 2-4: One group emphasized, rest greyed
% =========================================================================
function plotGroupEmphasis(ax, pts, evts, xCol, yCol, xData, yData, ...
        inBox, rect, showBounds, gMask, gColor, gName, ...
        anomalyMask, anomalyStyle)

    % --- Grey background: all non-group points ---
    bg = ~gMask & inBox;
    if any(bg)
        scatter(ax, xData(bg), yData(bg), 35, [0.5 0.5 0.5], 'filled', ...
            'MarkerFaceAlpha', 0.2);
    end
    hold(ax, 'on');
    bgOut = ~gMask & ~inBox;
    if any(bgOut)
        scatter(ax, xData(bgOut), yData(bgOut), 35, 'Marker', 'x', ...
            'MarkerEdgeColor', [0.5 0.5 0.5], 'MarkerEdgeAlpha', 0.2, ...
            'LineWidth', 0.5);
    end

    % --- Group points: in-bounds, colored ---
    gIn = gMask & inBox;
    if any(gIn)
        scatter(ax, xData(gIn), yData(gIn), 70, gColor, 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    end

    % --- Group points: out-of-bounds, x markers ---
    gOut = gMask & ~inBox;
    if any(gOut)
        scatter(ax, xData(gOut), yData(gOut), 70, gColor, ...
            'Marker', 'x', 'LineWidth', 2.0);
    end

    % --- Anomaly rings on this group's points (fixed size) ---
    groupAnomalies = gMask & anomalyMask;
    drawAnomalies(ax, xData, yData, groupAnomalies, anomalyStyle);

    drawRect(ax, rect, showBounds);
    hold(ax, 'off');
    grid(ax, 'on');
    colorbar(ax);

    ax.UserData.pts         = pts;
    ax.UserData.evts        = evts;
    ax.UserData.xCol        = xCol;
    ax.UserData.yCol        = yCol;
    ax.UserData.groupLabels = repmat("", height(pts), 1);
    ax.UserData.groupLabels(gMask) = string(gName);
    ax.UserData.anomalyMask = anomalyMask;
end

% =========================================================================
%  Shared helpers
% =========================================================================
function drawRect(ax, rect, showBounds)
    if showBounds
        rectangle(ax, 'Position', ...
            [rect(1), rect(3), rect(2)-rect(1), rect(4)-rect(3)], ...
            'EdgeColor', [0.2 0.7 0.2], 'LineWidth', 1.5, 'LineStyle', '--');
    end
end

function txt = groupDataCursorFcn(~, event)
    ax  = get(event.Target, 'Parent');
    ud  = ax.UserData;
    pos = event.Position;

    pts  = ud.pts;
    evts = ud.evts;
    xCol = ud.xCol;
    yCol = ud.yCol;

    xData = pts.(xCol);
    yData = pts.(yCol);

    d = (xData - pos(1)).^2 + (yData - pos(2)).^2;
    [~, idx] = min(d);

    eid     = char(pts.EventID(idx));
    eidDisp = strrep(eid, '_', '\_');
    xDisp   = strrep(xCol, '_', '\_');
    yDisp   = strrep(yCol, '_', '\_');

    txt = { ...
        sprintf('EventID: %s', eidDisp), ...
        sprintf('%s: %.4g', xDisp, xData(idx)), ...
        sprintf('%s: %.4g', yDisp, yData(idx))};

    evtIdx = find(evts.EventID == string(eid), 1);
    if ~isempty(evtIdx)
        txt{end+1} = sprintf('Date: %s',  char(string(evts.Date(evtIdx))));
        txt{end+1} = sprintf('Log#: %d',  evts.LogNumber(evtIdx));
        txt{end+1} = sprintf('Run#: %d',  evts.RunNumber(evtIdx));
        txt{end+1} = sprintf('Meep: %s',  char(evts.Meep(evtIdx)));
    end

    ptCols = pts.Properties.VariableNames;
    if ismember('EntityID', ptCols)
        entVal = pts.EntityID(idx);
        if isnumeric(entVal)
            txt{end+1} = sprintf('EntityID: %d', entVal);
        else
            txt{end+1} = sprintf('EntityID: %s', char(string(entVal)));
        end
    end
    if ismember('Flag', ptCols)
        txt{end+1} = sprintf('Flag: %s', char(string(pts.Flag(idx))));
    end

    % Group label
    if isfield(ud, 'groupLabels')
        gl = ud.groupLabels(idx);
        if gl ~= ""
            txt{end+1} = sprintf('Group: %s', strrep(char(gl), '_', '\_'));
        end
    end

    % Anomaly tag
    if isfield(ud, 'anomalyMask') && ud.anomalyMask(idx)
        txt{end+1} = 'ANOMALY';
    end
end