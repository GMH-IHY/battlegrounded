--!strict
-- Perf (ModuleScript)
-- Location: ReplicatedStorage > Movement > Perf
--
-- Tiny per-system timer for finding what costs frame time. Each movement system adds the time
-- its per-frame step took; the Performance test suite reads and resets the totals. Only
-- counts while `enabled` is true (the test turns it on), so it costs nothing otherwise.

local Perf = {}

Perf.enabled = false
local totals: { [string]: number } = {}
local counts: { [string]: number } = {}

function Perf.add(name: string, seconds: number)
	totals[name] = (totals[name] or 0) + seconds
end

function Perf.count(name: string, amount: number)
	counts[name] = (counts[name] or 0) + amount
end

function Perf.reset()
	table.clear(totals)
	table.clear(counts)
end

function Perf.snapshot(): ({ [string]: number }, { [string]: number })
	return table.clone(totals), table.clone(counts)
end

return Perf
