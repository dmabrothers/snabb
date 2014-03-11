--types for NetBSD sysctl, incomplete at present

local require = require

local c = require "syscall.netbsd.constants"

-- TODO we need to support more levels, and simplify a bit
-- TODO maybe we put these into the table below eg "kern" = c.KERN, "kern.pipe" = c.KERN_PIPE
-- note also some of the node constants do not have names, will just have to put numbers in
local map = {
  [c.CTL.KERN] = c.KERN,
  [c.CTL.HW] = c.HW,
  [c.CTL.VM] = c.VM,
}

local map2 = {
  [c.CTL.KERN] = {
    [c.KERN.PIPE] = c.KERN_PIPE,
    [c.KERN.TKSTAT] = c.KERN_TKSTAT,
  }
}

-- TODO these have no constants
--[[
#define CTL_NET_NAMES { \
        { 0, 0 }, \
        { "local", CTLTYPE_NODE }, \
        { "inet", CTLTYPE_NODE }, \
        { "implink", CTLTYPE_NODE }, \
        { "pup", CTLTYPE_NODE }, \
        { "chaos", CTLTYPE_NODE }, \
        { "xerox_ns", CTLTYPE_NODE }, \
        { "iso", CTLTYPE_NODE }, \
        { "emca", CTLTYPE_NODE }, \
        { "datakit", CTLTYPE_NODE }, \
        { "ccitt", CTLTYPE_NODE }, \
        { "ibm_sna", CTLTYPE_NODE }, \
        { "decnet", CTLTYPE_NODE }, \
        { "dec_dli", CTLTYPE_NODE }, \
        { "lat", CTLTYPE_NODE }, \
        { "hylink", CTLTYPE_NODE }, \
        { "appletalk", CTLTYPE_NODE }, \
        { "oroute", CTLTYPE_NODE }, \
        { "link_layer", CTLTYPE_NODE }, \
        { "xtp", CTLTYPE_NODE }, \
        { "coip", CTLTYPE_NODE }, \
        { "cnt", CTLTYPE_NODE }, \
        { "rtip", CTLTYPE_NODE }, \
        { "ipx", CTLTYPE_NODE }, \
        { "inet6", CTLTYPE_NODE }, \
        { "pip", CTLTYPE_NODE }, \
        { "isdn", CTLTYPE_NODE }, \
        { "natm", CTLTYPE_NODE }, \
        { "arp", CTLTYPE_NODE }, \
        { "key", CTLTYPE_NODE }, \
        { "ieee80211", CTLTYPE_NODE }, \
        { "mlps", CTLTYPE_NODE }, \
        { "route", CTLTYPE_NODE }, \
}
]]

-- TODO some of the friendly names do not map exactly to the constants, what should we do?

-- TODO note some could be considered bool not int eg KERN_FSYNC
local types = {
  ["kern.ostype"]    = "string",
  ["kern.osrelease"] = "string",
  ["kern.osrev"]     = "int",
  ["kern.version"]   = "string",
  ["kern.maxvnodes"] = "int",
  ["kern.maxproc"]   = "int",
  ["kern.maxfiles"]  = "int",
  ["kern.argmax"]    = "int",
  ["kern.securelvl"] = "int",
  ["kern.hostname"]  = "string",
  ["kern.hostid"]    = "int",
  ["kern.clockrate"] = "clockinfo",
-- KERN_VNODE              13      /* struct: vnode structures */
-- KERN_PROC               14      /* struct: process entries */
-- KERN_FILE               15      /* struct: file entries */
-- KERN_PROF               16      /* node: kernel profiling info */
  ["kern.posix1"]    = "int",
  ["kern.ngroups"]   = "int",
  ["kern.job_control"] = "int",
  ["kern.saved_ids"] = "int",
-- KERN_OBOOTTIME          21      /* struct: time kernel was booted */
  ["kern.domainname"] = "string",
  ["kern.maxpartitions"] = "int",
  ["kern.rawpartition"] = "int",
-- KERN_NTPTIME            25      /* struct: extended-precision time */
-- KERN_TIMEX              26      /* struct: ntp timekeeping state */
  ["kern.autonicetime"] = "int",
  ["kern.autoniceval"] = "int",
  ["kern.rtc_offset"] = "int",
  ["kern.root_device"] = "string",
  ["kern.msgbufsize"] = "int",
  ["kern.fsync"] = "int",
  ["kern.synchronized_io"] = "int",
  ["kern.iov_max"] = "int",
-- KERN_MBUF               39      /* node: mbuf parameters */
  ["kern.mapped_files"] = "int",
  ["kern.memlock"] = "int",
  ["kern.memlock_range"] = "int",
  ["kern.memory_protection"] = "int",
  ["kern.login_name_max"] = "int",
  ["kern.logsigexit"] = "int",
-- KERN_PROC2              47      /* struct: process entries */
-- KERN_PROC_ARGS          48      /* struct: process argv/env */
  ["kern.fscale"] = "int",
-- KERN_CP_TIME            51      /* struct: CPU time counters */
-- KERN_MSGBUF             53      /* kernel message buffer */
-- KERN_CONSDEV            54      /* dev_t: console terminal device */
  ["kern.maxptys"] = "int",
  ["kern.pipe.maxkvasz"] = "int",
  ["kern.pipe.maxloankvasz"] = "int",
  ["kern.pipe.maxbigpipes"] = "int",
  ["kern.pipe.nbigpipes"] = "int",
  ["kern.pipe.kvasize"] = "int",
  ["kern.maxphys"] = "int",
  ["kern.sbmax"] = "int",
  ["kern.tkstat.nin"] = "int64",
  ["kern.tkstat.nout"] = "int64",
  ["kern.tkstat.cancc"] = "int64",
  ["kern.tkstat.rawcc"] = "int64",
  ["kern.monotonic_clock"] = "int",
  ["kern.urnd"] = "int",
  ["kern.labelsector"] = "int",
  ["kern.labeloffset"] = "int",
-- KERN_LWP                64      /* struct: lwp entries */
  ["kern.forkfsleep"] = "int",
  ["kern.posix_threads"] = "int",
  ["kern.posix_semaphores"] = "int",
  ["kern.posix_barriers"] = "int",
  ["kern.posix_timers"] = "int",
  ["kern.posix_spin_locks"] = "int",
  ["kern.posix_reader_writer_locks"] = "int",
  ["kern.dump_on_panic"] = "int",
  ["kern.somaxkva"] = "int",
  ["kern.root_partition"] = "int",
-- KERN_DRIVERS            75      /* struct: driver names and majors #s */
-- KERN_BUF                76      /* struct: buffers */
-- KERN_FILE2              77      /* struct: file entries */
-- KERN_VERIEXEC           78      /* node: verified exec */
-- KERN_CP_ID              79      /* struct: cpu id numbers */
  ["kern.hardclock_ticks"] = "int",
-- KERN_ARND               81      /* void *buf, size_t siz random */
-- KERN_SYSVIPC            82      /* node: SysV IPC parameters */
-- KERN_BOOTTIME           83      /* struct: time kernel was booted */
-- KERN_EVCNT              84      /* struct: evcnts */

  ["hw.machine"] = "string",
  ["hw.model"] = "string",
  ["hw.ncpu"] = "int",
  ["hw.byteorder"] = "int",
  ["hw.physmem"] = "int",
  ["hw.usermem"] = "int",
  ["hw.pagesize"] = "int",
  ["hw.disknames"] = "string", -- also called drivenames
--["hw.iostats"] = "iostat[]" -- also called drivestats
  ["hw.machine_arch"] = "string",
  ["hw.alignbytes"] = "int",
  ["hw.cnmagic"] = "string",
  ["hw.physmem64"] = "int64",
  ["hw.usermem64"] = "int64",
  ["hw.ncpuonline"] = "int",

  ["vm.meter"] = "vmtotal", -- also named vm.vmmeter
  ["vm.loadavg"] = "loadavg",
--["vm.uvmexp" = "uvmexp",
  ["vm.nkmempages"] = "int",
--["vm.uvmexp2"] = "uvmexp_sysctl",
  ["vm.anonmin"] = "int",
  ["vm.execmin"] = "int",
  ["vm.filemin"] = "int",
  ["vm.maxslp"] = "int",
  ["vm.uspace"] = "int",
  ["vm.anonmax"] = "int",
  ["vm.execmax"] = "int",
  ["vm.filemax"] = "int",

-- ip
--[[
        { "forwarding", CTLTYPE_INT }, \
        { "redirect", CTLTYPE_INT }, \
        { "ttl", CTLTYPE_INT }, \
        { "mtu", CTLTYPE_INT }, \
        { "forwsrcrt", CTLTYPE_INT }, \
        { "directed-broadcast", CTLTYPE_INT }, \
        { "allowsrcrt", CTLTYPE_INT }, \
        { "subnetsarelocal", CTLTYPE_INT }, \
        { "mtudisc", CTLTYPE_INT }, \
        { "anonportmin", CTLTYPE_INT }, \
        { "anonportmax", CTLTYPE_INT }, \
        { "mtudisctimeout", CTLTYPE_INT }, \
        { "maxflows", CTLTYPE_INT }, \
        { "hostzerobroadcast", CTLTYPE_INT }, \
        { "gifttl", CTLTYPE_INT }, \
        { "lowportmin", CTLTYPE_INT }, \
        { "lowportmax", CTLTYPE_INT }, \
        { "maxfragpackets", CTLTYPE_INT }, \
        { "grettl", CTLTYPE_INT }, \
        { "checkinterface", CTLTYPE_INT }, \
        { "ifq", CTLTYPE_NODE }, \
        { "random_id", CTLTYPE_INT }, \
        { "do_loopback_cksum", CTLTYPE_INT }, \
        { "stats", CTLTYPE_STRUCT }, \
--]]
}

return {types = types, map = map, map2 = map2}

