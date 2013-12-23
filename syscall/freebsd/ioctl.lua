-- ioctls, filling in as needed

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local s, t = types.s, types.t

local strflag = require("syscall.helpers").strflag
local bit = require "syscall.bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296ULL end -- TODO see note in NetBSD
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

local IOC = {
  VOID  = 0x20000000,
  OUT   = 0x40000000,
  IN    = 0x80000000,
  PARM_SHIFT  = 13,
}

IOC.PARM_MASK = lshift(1, IOC.PARM_SHIFT) - 1
IOC.INOUT = IOC.IN + IOC.OUT
IOC.DIRMASK = IOC.IN + IOC.OUT + IOC.VOID

local function ioc(dir, ch, nr, size)
  return t.ulong(bor(dir,
                 lshift(band(size, IOC.PARM_MASK), 16),
                 lshift(ch, 8),
                 nr))
end

local singletonmap = {
  int = "int1",
  char = "char1",
  uint = "uint1",
  uint64 = "uint64_1",
  off_t = "off1",
}

local function _IOC(dir, ch, nr, tp)
  if type(ch) == "string" then ch = ch:byte() end
  if type(tp) == "number" then return ioc(dir, ch, nr, tp) end
  local size = s[tp]
  local singleton = singletonmap[tp] ~= nil
  tp = singletonmap[tp] or tp
  return {number = ioc(dir, ch, nr, size),
          read = dir == IOC.OUT or dir == IOC.INOUT, write = dir == IOC.IN or dir == IOC.INOUT,
          type = t[tp], singleton = singleton}
end

local _IO     = function(ch, nr)     return _IOC(IOC.VOID, ch, nr, 0) end
local _IOR    = function(ch, nr, tp) return _IOC(IOC.OUT, ch, nr, tp) end
local _IOW    = function(ch, nr, tp) return _IOC(IOC.IN, ch, nr, tp) end
local _IOWR   = function(ch, nr, tp) return _IOC(IOC.INOUT, ch, nr, tp) end
local _IOWINT = function(ch, nr)     return _IOC(IOC.VOID, ch, nr, "int") end

local ioctl = strflag {
  -- tty ioctls
  TIOCEXCL       =  _IO('t', 13),
  TIOCNXCL       =  _IO('t', 14),
  TIOCGPTN       = _IOR('t', 15, "int"),
  TIOCFLUSH      = _IOW('t', 16, "int"),
  TIOCGETA       = _IOR('t', 19, "termios"),
  TIOCSETA       = _IOW('t', 20, "termios"),
  TIOCSETAW      = _IOW('t', 21, "termios"),
  TIOCSETAF      = _IOW('t', 22, "termios"),
  TIOCGETD       = _IOR('t', 26, "int"),
  TIOCSETD       = _IOW('t', 27, "int"),
  TIOCPTMASTER   =  _IO('t', 28),
  TIOCGDRAINWAIT = _IOR('t', 86, "int"),
  TIOCSDRAINWAIT = _IOW('t', 87, "int"),
  TIOCTIMESTAMP  = _IOR('t', 89, "timeval"),
  TIOCMGDTRWAIT  = _IOR('t', 90, "int"),
  TIOCMSDTRWAIT  = _IOW('t', 91, "int"),
  TIOCDRAIN      =  _IO('t', 94),
  TIOCSIG        = _IOWINT('t', 95),
  TIOCEXT        = _IOW('t', 96, "int"),
  TIOCSCTTY      =  _IO('t', 97),
  TIOCCONS       = _IOW('t', 98, "int"),
  TIOCGSID       = _IOR('t', 99, "int"),
  TIOCSTAT       =  _IO('t', 101),
  TIOCUCNTL      = _IOW('t', 102, "int"),
  TIOCSWINSZ     = _IOW('t', 103, "winsize"),
  TIOCGWINSZ     = _IOR('t', 104, "winsize"),
  TIOCMGET       = _IOR('t', 106, "int"),

  -- file descriptor ioctls
  FIOCLEX        =  _IO('f', 1),
  FIONCLEX       =  _IO('f', 2),
  FIONREAD       = _IOR('f', 127, "int"),
  FIONBIO        = _IOW('f', 126, "int"),
  FIOASYNC       = _IOW('f', 125, "int"),
  FIOSETOWN      = _IOW('f', 124, "int"),
  FIOGETOWN      = _IOR('f', 123, "int"),
  FIODTYPE       = _IOR('f', 122, "int"),
  FIOGETLBA      = _IOR('f', 121, "int"),
  FIODGNAME      = _IOW('f', 120, "fiodgname_arg"),
  FIONWRITE      = _IOR('f', 119, "int"),
  FIONSPACE      = _IOR('f', 118, "int"),
  FIOSEEKDATA    = _IOWR('f', 97, "off_t"),
  FIOSEEKHOLE    = _IOWR('f', 98, "off_t"),

-- allow user defined ioctls
  _IO = _IO,
  _IOR = _IOR, 
  _IOW = _IOW,
  _IOWR = _IOWR,
  _IOWINT = _IOWINT,
}

return ioctl

end

return {init = init}

