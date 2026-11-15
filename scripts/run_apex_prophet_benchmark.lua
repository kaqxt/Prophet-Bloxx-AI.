-- Run from repository root: lua scripts/run_apex_prophet_benchmark.lua
package.path="./scripts/?.lua;"..package.path
local Benchmark=require("apex_prophet_benchmark")
local report=Benchmark.run({duration=1.2})
io.write(Benchmark.format(report),"\n")
io.write("Summary: episodes=",tostring(report.summary.episodes),
    " goal_difference=",tostring(report.summary.goal_difference),
    " mean_touch_rate=",tostring(report.summary.mean_touch_rate),
    " mean_position_error=",tostring(report.summary.mean_position_error),"\n")
if report.failed>0 then os.exit(1) end
