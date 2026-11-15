-- Run from repository root: lua scripts/run_apex_prophet_tuning.lua
package.path="./scripts/?.lua;"..package.path
local Tuner=require("apex_prophet_tuner")
local result=Tuner.run({duration=0.4,max_trials=8})
io.write(Tuner.format(result),"\n")
if not result.best or result.best.report.failed>0 then os.exit(1) end
