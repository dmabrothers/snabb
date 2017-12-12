module(..., package.seeall)

local S = require("syscall")
local shm = require("core.shm")
local timer = require("core.timer")
local engine = require("core.app")
local config = require("core.config")
local counter = require("core.counter")

CSVStatsTimer = {}

local function open_link_counters(pid)
   local counters = {}
   for _, linkspec in ipairs(shm.children("/"..pid.."/links")) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      local link = shm.open_frame("/"..pid.."/links/"..linkspec)
      if not counters[fa] then counters[fa] = {input={},output={}} end
      if not counters[ta] then counters[ta] = {input={},output={}} end
      counters[fa].output[fl] = link
      counters[ta].input[tl] = link
   end
   return counters
end

-- A timer that monitors packet rate and bit rate on a set of links,
-- printing the data out to a CSV file.
--
-- Standard mode example (default):
--
-- Time (s),decap MPPS,decap Gbps,encap MPPS,encap Gbps
-- 0.999197,3.362784,13.720160,3.362886,15.872824
-- 1.999181,3.407569,13.902880,3.407569,16.083724
--
-- Hydra mode example:
--
-- benchmark,id,score,unit
-- decap_mpps,1,3.362784,mpps
-- decap_gbps,1,13.720160,gbps
-- encap_mpps,1,3.362886,mpps
-- encap_gbps,1,15.872824,gbps
-- decap_mpps,2,3.407569,mpps
-- decap_gbps,2,13.902880,gbps
-- encap_mpps,2,3.407569,mpps
-- encap_gbps,2,16.083724,gbps
--
function CSVStatsTimer:new(filename, hydra_mode, pid)
   local file = filename and io.open(filename, "w") or io.stdout
   local o = { hydra_mode=hydra_mode, link_data={}, file=file, period=1,
      header = hydra_mode and "benchmark,id,score,unit" or "Time (s)" }
   o.pid = pid or S.getpid()
   o.links_by_app = open_link_counters(o.pid)
   return setmetatable(o, {__index = CSVStatsTimer})
end

-- Add links from an app whose identifier is ID to the CSV timer.  If
-- present, LINKS is an array of strings identifying a subset of links
-- to monitor.  The optional LINK_NAMES table maps link names to
-- human-readable names, for the column headers.
function CSVStatsTimer:add_app(id, links, link_names)
   local function add_link_data(name, link)
      local link_name = link_names[name] or name
      if not self.hydra_mode then
         local h = (',%s MPPS,%s Gbps'):format(link_name, link_name)
         self.header = self.header..h
      end
      local data = {
         link_name = link_name,
         txpackets = link.txpackets,
         txbytes = link.txbytes,
      }
      table.insert(self.link_data, data)
   end

   local app = assert(self.links_by_app[id], "App named "..id.." not found")
   for _,name in ipairs(links) do
      local link = app.input[name] or app.output[name]
      assert(link, "Link named "..name.." not found in "..id)
      add_link_data(name, link)
   end
end

function CSVStatsTimer:set_period(period) self.period = period end

-- Activate the timer with a period of PERIOD seconds.
function CSVStatsTimer:activate()
   self.file:write(self.header..'\n')
   self.file:flush()
   self.start = engine.now()
   self.prev_elapsed = 0
   for _,data in ipairs(self.link_data) do
      data.prev_txpackets = counter.read(data.txpackets)
      data.prev_txbytes = counter.read(data.txbytes)
   end
   local function tick() return self:tick() end
   local t = timer.new('csv_stats', tick, self.period*1e9, 'repeating')
   timer.activate(t)
   return t
end

function CSVStatsTimer:tick()
   local elapsed = engine.now() - self.start
   local dt = elapsed - self.prev_elapsed
   self.prev_elapsed = elapsed
   if not self.hydra_mode then
      self.file:write(('%f'):format(elapsed))
   end
   for _,data in ipairs(self.link_data) do
      local txpackets = counter.read(data.txpackets)
      local txbytes = counter.read(data.txbytes)
      local diff_txpackets = tonumber(txpackets - data.prev_txpackets) / dt / 1e6
      local diff_txbytes = tonumber(txbytes - data.prev_txbytes) * 8 / dt / 1e9
      data.prev_txpackets = txpackets
      data.prev_txbytes = txbytes
      if self.hydra_mode then
         -- Hydra reports seem to prefer integers for the X (time) axis.
         self.file:write(('%s_mpps,%.f,%f,mpps\n'):format(
            data.link_name,elapsed,diff_txpackets))
         self.file:write(('%s_gbps,%.f,%f,gbps\n'):format(
            data.link_name,elapsed,diff_txbytes))
      else
         self.file:write((',%f'):format(diff_txpackets))
         self.file:write((',%f'):format(diff_txbytes))
      end
   end
   if not self.hydra_mode then
      self.file:write('\n')
   end
   self.file:flush()
end
