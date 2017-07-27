-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- NDP address resolution (RFC 4861)

-- Given a remote IPv6 address, try to find out its MAC address.
-- If resolution succeeds:
-- All packets coming through the 'south' interface (ie, via the network card)
-- are silently forwarded (unless dropped by the network card).
-- All packets coming through the 'north' interface (the lwaftr) will have
-- their Ethernet headers rewritten.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local packet   = require("core.packet")
local link     = require("core.link")
local lib      = require("core.lib")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6     = require("lib.protocol.ipv6")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")

local C = ffi.C
local htons, ntohs = lib.htons, lib.ntohs
local htonl, ntohl = lib.htonl, lib.ntohl
local receive, transmit = link.receive, link.transmit
local rd16, wr16, wr32, ipv6_equals = lwutil.rd16, lwutil.wr16, lwutil.wr32, lwutil.ipv6_equals

local option_source_link_layer_address = 1
local option_target_link_layer_address = 2
local eth_ipv6_size = constants.ethernet_header_size + constants.ipv6_fixed_header_size
local o_icmp_target_offset = 8
local o_icmp_first_option = 24

-- Cache constants
local ipv6_pseudoheader_size = constants.ipv6_pseudoheader_size
local ethernet_header_size = constants.ethernet_header_size
local o_ipv6_src_addr =  constants.o_ipv6_src_addr
local o_ipv6_dst_addr =  constants.o_ipv6_dst_addr
local o_ipv6_payload_len = constants.o_ipv6_payload_len
local o_ipv6_hop_limit = constants.o_ipv6_hop_limit
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local proto_icmpv6 = constants.proto_icmpv6
local icmpv6_na = constants.icmpv6_na
local icmpv6_ns = constants.icmpv6_ns
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local ethertype_ipv6 = constants.ethertype_ipv6

-- Special addresses
local ipv6_all_nodes_local_segment_addr = ipv6:pton("ff02::1")
local ipv6_unspecified_addr = ipv6:pton("0::0") -- aka ::/128
-- Really just the first 13 bytes of the following...
local ipv6_solicited_multicast = ipv6:pton("ff02:0000:0000:0000:0000:0001:ff00:00")


local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ipv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t v_tc_fl; // version, tc, flow_label
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
} __attribute__((packed))
]]
local icmpv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  code;
   uint16_t checksum;
} __attribute__((packed))
]]
local na_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t flags;               /* Bit 31: Router; Bit 30: Solicited;
                                    Bit 29: Override; Bits 28-0: Reserved. */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local ns_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t flags;               /* Bits 31-0: Reserved.  */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local option_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  length;
} __attribute__((packed))
]]
local ether_option_header_t = ffi.typeof ([[
/* All values in network byte order.  */
struct {
   $ header;
   uint8_t  addr[6];
} __attribute__((packed))
]], option_header_t)

local ndp_header_t = ffi.typeof([[
struct {
   $ ether;
   $ ipv6;
   $ icmpv6;
   uint8_t body[0];
} __attribute__((packed))]], ether_header_t, ipv6_header_t, icmpv6_header_t)
local ndp_header_len = ffi.sizeof(ndp_header_t)

local function ptr_to(t) return ffi.typeof('$*', t) end
local ndp_header_ptr_t = ptr_to(ndp_header_t)
local na_header_ptr_t = ptr_to(na_header_t)
local ns_header_ptr_t = ptr_to(ns_header_t)
local option_header_ptr_t = ptr_to(option_header_t)
local ether_option_header_ptr_t = ptr_to(ether_option_header_t)

local ether_type_ipv6 = 0x86DD

local na_router_bit = 31
local na_solicited_bit = 30
local na_override_bit = 29

local ipv6_pseudoheader_t = ffi.typeof [[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t ulp_length;
   uint32_t next_header;
} __attribute__((packed))
]]
local function checksum_pseudoheader_from_header(ipv6_fixed_header)
   local ph = ipv6_pseudoheader_t()
   ph.src_ip = ipv6_fixed_header.src_ip
   ph.dst_ip = ipv6_fixed_header.dst_ip
   ph.ulp_length = htonl(ntohs(ipv6_fixed_header.payload_length))
   ph.next_header = htonl(ipv6_fixed_header.next_header)
   return checksum.ipsum(ffi.cast('char*', ph),
                         ffi.sizeof(ipv6_pseudoheader_t), 0)
end

local function is_ndp(pkt)
   if pkt.length < ndp_header_len then return false end
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   if ntohs(h.ether.type) ~= ether_type_ipv6 then return false end
   if h.ipv6.next_header ~= proto_icmpv6 then return false end
   return h.icmpv6.type >= 133 and h.icmpv6.type <= 137
end

local function make_ndp_packet(src_mac, dst_mac, src_ip, dst_ip, message_type,
                               message, option)
   local pkt = packet.allocate()
   local ptr

   ptr, pkt.length = pkt.data, ndp_header_len
   local h = ffi.cast(ndp_header_ptr_t, ptr)
   h.ether.dhost = dst_mac
   h.ether.shost = src_mac
   h.ether.type = htons(ethertype_ipv6)
   h.ipv6.v_tc_fl = 0
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 0, 4, 6)  -- IPv6 Version
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 4, 8, 1)  -- Traffic class
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 12, 20, 0) -- Flow label
   h.ipv6.payload_length = 0
   h.ipv6.next_header = proto_icmpv6
   h.ipv6.hop_limit = 255
   h.ipv6.src_ip = src_ip
   h.ipv6.dst_ip = dst_ip
   h.icmpv6.type = message_type
   h.icmpv6.code = 0
   h.icmpv6.checksum = 0

   ptr, pkt.length = pkt.data + pkt.length, pkt.length + ffi.sizeof(message)
   ffi.copy(ptr, message, ffi.sizeof(message))

   ptr, pkt.length = pkt.data + pkt.length, pkt.length + ffi.sizeof(option)
   ffi.copy(ptr, option, ffi.sizeof(option))

   -- Now fix up lengths and checksums.
   h.ipv6.payload_length = htons(pkt.length - ffi.sizeof(ether_header_t))
   ptr = ffi.cast('char*', h.icmpv6)
   local base_checksum = checksum_pseudoheader_from_header(h.ipv6)
   h.icmpv6.checksum = htons(checksum.ipsum(ptr,
                                            pkt.length - (ptr - pkt.data),
                                            bit.bnot(base_checksum)))
   return pkt
end

-- Respond to a neighbor solicitation for our own address.
local function make_na_packet(src_mac, dst_mac, src_ip, dst_ip, is_router)
   local message = na_header_t()
   local flags = bit.lshift(1, na_solicited_bit)
   if is_router then
      flags = bit.bor(bit.lshift(1, na_router_bit), flags)
   end
   message.flags = htonl(flags)
   message.target_ip = src_ip

   local option = ether_option_header_t()
   option.header.type = option_target_link_layer_address
   option.header.length = 1 -- One 8-byte unit.
   option.addr = src_mac

   return make_ndp_packet(src_mac, dst_mac, src_ip, dst_ip, icmpv6_na,
                          message, option)
end

-- Solicit a neighbor's address.
local function make_ns_packet(src_mac, src_ip, dst_ip)
   local message = ns_header_t()
   message.flags = 0
   message.target_ip = dst_ip

   local option = ether_option_header_t()
   option.header.type = option_source_link_layer_address
   option.header.length = 1 -- One 8-byte unit.
   option.addr = src_mac

   local broadcast_mac = ethernet:pton("ff:ff:ff:ff:ff:ff")
   return make_ndp_packet(src_mac, broadcast_mac, src_ip, dst_ip, icmpv6_ns,
                          message, option)
end

local function verify_icmp_checksum(pkt)
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   local ph_csum = checksum_pseudoheader_from_header(h.ipv6)
   local icmp_length = ntohs(h.ipv6.payload_length)
   local a = checksum.ipsum(ffi.cast('char*', h.icmpv6), icmp_length,
                            bit.bnot(ph_csum))
   return a == 0
end

-- IPv6 multicast addresses start with FF.
local function is_address_multicast(ipv6_addr)
   return ipv6_addr[0] == 0xff
end

-- Solicited multicast addresses have their first 13 bytes set to
-- ff02::1:ff00:0/104, aka ff02:0000:0000:0000:0000:0001:ff[UV:WXYZ].
local function is_solicited_node_multicast_address(addr)
   return C.memcmp(addr, ipv6_solicited_multicast, 13) == 0
end

local function random_locally_administered_unicast_mac_address()
   local mac = lib.random_bytes(6)
   -- Bit 0 is 0, indicating unicast.  Bit 1 is 1, indicating locally
   -- administered.
   mac[0] = bit.lshift(mac[0], 2) + 2
   return mac
end

NDP = {}
local ndp_config_params = {
   -- Source MAC address will default to a random address.
   self_mac  = { default=false },
   -- Source IP is required though.
   self_ip   = { required=true },
   -- The next-hop MAC address can be statically configured.
   next_mac  = { default=false },
   -- But if the next-hop MAC isn't configured, NDP will figure it out.
   next_ip   = { default=false },
   is_router = { default=true }
}

function NDP:new(conf)
   local o = lib.parse(conf, ndp_config_params)
   if not o.self_mac then
      o.self_mac = random_locally_administered_unicast_mac_address()
   end
   if not o.next_mac then
      assert(o.next_ip, 'NDP needs next-hop IPv6 address to learn next-hop MAC')
      self.ns_interval = 3 -- Send a new NS every three seconds.
   end
   return setmetatable(o, {__index=NDP})
end

function NDP:maybe_send_ns_request (output)
   if self.next_mac then return end
   self.next_ns_time = self.next_ns_time or engine.now()
   if self.next_ns_time <= engine.now() then
      print(("NDP: Resolving '%s'"):format(ipv6:ntop(self.next_ip)))
      transmit(self.output.south,
               make_ns_packet(self.self_mac, self.self_ip, self.next_ip))
      self.next_ns_time = engine.now() + self.ns_interval
   end
end

function NDP:resolve_next_hop(next_mac)
   -- It's possible for a NA packet to indicate the MAC address in
   -- more than one way (e.g. unicast ethernet source address and the
   -- link layer address in the NDP options).  Just take the first
   -- one.
   if self.next_mac then return end
   print(("NDP: '%s' resolved (%s)"):format(ipv6:ntop(self.next_ip),
                                            ethernet:ntop(next_mac)))
   self.next_mac = next_mac
end

local function copy_mac(src)
   local dst = ffi.new('uint8_t[6]')
   ffi.copy(dst, src, 6)
   return dst
end

function NDP:handle_ndp (pkt)
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   -- Generic checks.
   if h.ipv6.hop_limit ~= 255 then return end
   if h.icmpv6.code ~= 0 then return end
   if not verify_icmp_checksum(pkt) then return end

   if h.icmpv6.type == icmpv6_na then
      -- Only process advertisements when we are looking for a
      -- next-hop MAC.
      if self.next_mac then return end
      -- Drop packets that are too short.
      if pkt.length < ndp_header_len + ffi.sizeof(na_header_t) then return end
      local na = ffi.cast(na_header_ptr_t, h.body)
      local solicited = bit.lshift(1, na_solicited_bit)
      -- Reject unsolicited advertisements.
      if bit.band(solicited, ntohl(na.flags)) ~= solicited then return end
      -- We only are looking for the MAC of our next-hop; no others.
      if not ipv6_equals(na.target_ip, self.next_ip) then return end
      -- First try to get the MAC from the options.
      local offset = na.options - pkt.data
      while offset < pkt.length do
         local option = ffi.cast(option_header_ptr_t, pkt.data + offset)
         -- Any option whose length is 0 or too large causes us to
         -- drop the packet.
         if option.length == 0 then return end
         if offset + option.length*8 > pkt.length then return end
         offset = offset + option.length*8
         if option.type == option_target_link_layer_address then
            if option.length ~= 1 then return end
            local ether = ffi.cast(ether_option_header_ptr_t, option)
            self:resolve_next_hop(copy_mac(ether.addr))
         end
      end
      -- Otherwise, when responding to unicast solicitations, the
      -- option can be omitted since the sender of the solicitation
      -- has the correct link-layer address.  See 4.4. Neighbor
      -- Advertisement Message Format.
      self:resolve_next_hop(copy_mac(h.ether.shost))
   elseif h.icmpv6.type == icmpv6_ns then
      if pkt.length < ndp_header_len + ffi.sizeof(ns_header_t) then return end
      local ns = ffi.cast(ns_header_ptr_t, h.body)
      if is_address_multicast(ns.target_ip) then return end
      if not ipv6_equals(ns.target_ip, self.self_ip) then return end
      local dst_ip
      if ipv6_equals(h.ipv6.src_ip, ipv6_unspecified_addr) then
         if is_solicited_node_multicast_address(h.ipv6.dst_ip) then return end
         dst_ip = ipv6_all_nodes_local_segment_addr
      else
         dst_ip = h.ipv6.src_ip
      end
      -- We don't need the options, but we do need to check them for
      -- validity.
      local offset = ns.options - pkt.data
      while offset < pkt.length do
         local option = ffi.cast(option_header_ptr_t, pkt.data + offset)
         -- Any option whose length is 0 or too large causes us to
         -- drop the packet.
         if option.length == 0 then return end
         if offset + option.length * 8 > pkt.length then return end
         offset = offset + option.length*8
         if option.type == option_source_link_layer_address then
            if ipv6_equals(h.ipv6.src_ip, ipv6_unspecified_addr) then
               return
            end
         end
      end
      link.transmit(self.output.south,
                    make_na_packet(self.self_mac, h.ether.shost,
                                   self.self_ip, dst_ip, self.is_router))
   else
      -- Unhandled NDP packet; silently drop.
      return
   end
end

function NDP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   -- TODO: do unsolicited neighbor advertisement on start and on
   -- configuration reloads?
   -- This would be an optimization, not a correctness issue
   self:maybe_send_ns_request(osouth)

   for _ = 1, link.nreadable(isouth) do
      local p = receive(isouth)
      if is_ndp(p) then
         self:handle_ndp(p)
         packet.free(p)
      else
         transmit(onorth, p)
      end
   end

   for _ = 1, link.nreadable(inorth) do
      local p = receive(inorth)
      if not self.next_mac then
         -- drop all southbound packets until the next hop's ethernet address is known
         packet.free(p)
      else
         ffi.copy(p.data, self.next_mac, 6)
         ffi.copy(p.data + 6, self.self_mac, 6)
         transmit(osouth, p)
      end
   end
end

function selftest()
   print("selftest: ndp")

   local config = require("core.config")
   local sink = require("apps.basic.basic_apps").Sink
   local c = config.new()
   config.app(c, "nd1", NDP, { self_ip  = ipv6:pton("2001:DB8::1"),
                               next_ip  = ipv6:pton("2001:DB8::2") })
   config.app(c, "nd2", NDP, { self_ip  = ipv6:pton("2001:DB8::2"),
                               next_ip  = ipv6:pton("2001:DB8::1") })
   config.app(c, "sink1", sink)
   config.app(c, "sink2", sink)
   config.link(c, "nd1.south -> nd2.south")
   config.link(c, "nd2.south -> nd1.south")
   config.link(c, "sink1.tx -> nd1.north")
   config.link(c, "nd1.north -> sink1.rx")
   config.link(c, "sink2.tx -> nd2.north")
   config.link(c, "nd2.north -> sink2.rx")
   engine.configure(c)
   engine.main({ duration = 0.1 })

   local function mac_eq(a, b) return C.memcmp(a, b, 6) == 0 end
   local nd1, nd2 = engine.app_table.nd1, engine.app_table.nd2
   assert(nd1.next_mac)
   assert(nd2.next_mac)
   assert(mac_eq(nd1.next_mac, nd2.self_mac))
   assert(mac_eq(nd2.next_mac, nd1.self_mac))

   print("selftest: ok")
end
