To make this work, you need to move `Date` from being an **event-level field derived by `NameParser`** to being a **point-level field produced by your evaluator**.

Right now the flow is:

`folder name -> NameParser -> manifest.Meta.Date -> EventTable.Date -> viewer annotation`

What you want is:

`MyEvaluator -> point-specific dates -> PointTable.Date -> viewer annotation`

## What must change

### 1. Stop relying on `NameParser` for `Date`

`NameParser` is currently parsing the folder name and populating `meta.Date`. That happens in:

* `MAC/+logdb/NameParser.m`
* consumed by `MAC/+logdb/ManifestBuilder.m`
* then written into the event row by `MAC/+logdb/PipelineRunner.m`

The key line is in `PipelineRunner.buildEventRow()`:

```matlab
row.Date       = meta.Date;
```

That is the main place where event dates are still being forced from folder names.

### 2. Add a `Date` column to the `Points` table in `MyEvaluator`

Your evaluator now needs to return a per-point date column.

In `MAC/+logdb/+eval/MyEvaluator.m`, wherever your function returns the date associated with each point, add it to the `points` table.

Conceptually, Step 3 changes from something like:

```matlab
[Entity_ID, Success_Flag, x1, y1, x2, y2] = function_XYZ(...);
```

to something like:

```matlab
[Entity_ID, Success_Flag, PointDate, x1, y1, x2, y2] = function_XYZ(...);
```

Then convert it to a column vector:

```matlab
PointDate = PointDate(:);
```

And add it into the points table:

```matlab
points = table( ...
    repmat(eventID, nEntities, 1), ...
    (1:nEntities)', ...
    PointDate, ...
    Entity_ID, ...
    Success_Flag, ...
    x1, ...
    y1, ...
    x2, ...
    y2, ...
    'VariableNames', { ...
        'EventID', ...
        'PointID', ...
        'Date', ...
        'EntityID', ...
        'Flag', ...
        'Plot1_X', ...
        'Plot1_Y', ...
        'Plot2_X', ...
        'Plot2_Y' ...
    } ...
);
```

That is the most important schema change.

## 3. Change the viewer datatip to read `Date` from the selected point, not the event

In `MAC/+logdb/Viewer.m`, the datatip currently does this:

```matlab
evtIdx = find(string(evts.EventID) == string(eid), 1);
if ~isempty(evtIdx)
    if ismember('Date', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Date: %s', char(string(evts.Date(evtIdx))));
    end
```

That is event-level behavior. Replace it so it first checks the point row:

```matlab
ptCols = pts.Properties.VariableNames;

if ismember('Date', ptCols)
    txt{end+1} = sprintf('Date: %s', char(string(pts.Date(idx))));
end
```

Then keep the event-level lookup only for true event metadata like `LogNumber`, `RunNumber`, `Site`, etc.

So the pattern should become:

```matlab
ptCols = pts.Properties.VariableNames;

if ismember('Date', ptCols)
    txt{end+1} = sprintf('Date: %s', char(string(pts.Date(idx))));
end

evtIdx = find(string(evts.EventID) == string(eid), 1);
if ~isempty(evtIdx)
    if ismember('LogNumber', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Log#: %d', evts.LogNumber(evtIdx));
    end
    if ismember('RunNumber', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Run#: %d', evts.RunNumber(evtIdx));
    end
    ...
end
```

Do the same in `MAC/+logdb/GroupViewer.m`, because it also currently pulls `Date` from `evts.Date(evtIdx)`.

## 4. Decide what to do with `EventTable.Date`

You have two clean options.

### Option A: remove event-level `Date` entirely

This is the cleanest if dates are now truly point-specific and not naturally event-specific.

Then in `PipelineRunner.buildEventRow()` remove:

```matlab
row.Date = meta.Date;
```

And do not require `Date` in the event table anymore.

This also means updating tests and docs.

### Option B: keep an event-level `Date`, but derive it from evaluator output

If you still want one event-level representative date for CSV filtering or summaries, compute it in `MyEvaluator` and put it in `result.Summary`, for example:

```matlab
summary.Date = PointDate(1);
```

or maybe:

```matlab
summary.DateStart = min(PointDate);
summary.DateEnd   = max(PointDate);
```

Then remove the folder-derived one from `PipelineRunner` and let the evaluator own it.

This is usually better than keeping `NameParser` as the source of truth.

## 5. Relax `NameParser` so it no longer parses a date

Right now `NameParser` enforces folder names like:

* `log##_mm_dd_yyyy_#_(a-z)#`
* `log##_mm_dd_yyyy_(a-z)#`

If you no longer want the folder name to carry date information, then `NameParser` needs a redesign.

At minimum:

* remove `Date` from its output struct
* update the regex patterns so they do not expect `mm_dd_yyyy`
* update `EventID` logic if needed

For example, if your future folder format is more like:

* `log##_#_(a-z)#`
* or some other non-date format

then `PATTERN_WITH_RUN` and `PATTERN_NO_RUN` both need to change accordingly.

If you still want to keep the old folder format for compatibility but just ignore the date, then you can leave the regex as-is and simply stop using `meta.Date`. But since you said you “no longer want to get the date from the log folder name,” I would remove it from the parser contract altogether.

## 6. Update tests

Your tests currently assume `Date` comes from `NameParser`.

Examples in `MAC/+logdb/tests/TestLogDB.m` that will need to change:

```matlab
tc.verifyEqual(meta.Date, datetime(2024, 1, 15));
```

and:

```matlab
tc.verifyTrue(ismember('Date', cols));
```

If you remove event-level `Date`, those should be replaced with checks on `PointTable.Date` instead.

For example:

```matlab
pts = db.getPoints();
tc.verifyTrue(ismember('Date', pts.Properties.VariableNames));
```

And parser tests should no longer expect `meta.Date`.

## 7. Update documentation

Your docs currently state that:

* `EventTable.Date` comes from `NameParser`
* `NameParser` parses the date from folder names

Those sections in `DOCUMENTATION.md` need to be revised so the schema reflects:

* point-level `Date` belongs in `PointTable`
* event-level date, if any, comes from evaluator summary, not folder parsing

---

# Minimal practical change set

If you want the smallest working fix without a full parser redesign, do this:

1. In `MyEvaluator`, add `Date` to `result.Points`.
2. In `Viewer.m`, change datatips to use `pts.Date(idx)`.
3. In `GroupViewer.m`, change datatips to use `pts.Date(idx)`.
4. Stop displaying `evts.Date(evtIdx)` in viewer annotations.
5. Optionally leave `NameParser` and `EventTable.Date` alone for now, even if it becomes legacy.

That gets you the behavior you want quickly.

# Cleaner long-term change set

If you want the architecture to match your new intent cleanly:

1. Remove `Date` from `NameParser`.
2. Remove `row.Date = meta.Date` from `PipelineRunner.buildEventRow()`.
3. Add point-level `Date` in `MyEvaluator`.
4. Make viewers read `Date` from `PointTable`.
5. If needed, add evaluator-derived summary dates to `EventTable`.
6. Update tests and docs.

# My recommendation

I would do the clean version:

* **PointTable.Date** = true source of annotation date
* **EventTable.Date** = either removed, or replaced by evaluator-derived summary date
* **NameParser** = no longer owns date at all

That matches your new “more granular database” idea much better and avoids having two competing date sources.

If you want, I can now turn this into the exact code edits for `MyEvaluator.m`, `Viewer.m`, `GroupViewer.m`, `PipelineRunner.m`, and `NameParser.m`.
