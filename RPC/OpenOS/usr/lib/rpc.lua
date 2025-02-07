local serial = require "serialization"
local computer = require "computer"
local minitel = require "minitel"
local event = require "event"
local rpcf = {}
local rpcrunning = false
local rpc = {}
rpc.port = 111

function rpc.call(hostname,fn,...)
 if hostname == "localhost" then
  return rpcf[fn](...)
 end
 local rv = minitel.genPacketID()
 minitel.rsend(hostname,rpc.port,serial.serialize({fn,rv,...}),true)
 local st = computer.uptime()
 local rt = {}
 repeat
  local _, from, port, data = event.pull(30, "net_msg", hostname, rpc.port)
  rt = serial.unserialize(data) or {}
 until rt[1] == rv or computer.uptime() > st + 30
 if rt[1] == rv then
  if rt[2] then
   return table.unpack(rt,3)
  end
  error(rt[3])
 end
 error("timed out")
end
function rpc.proxy(hostname,filter)
 filter=(filter or "").."(.+)"
 local fnames = rpc.call(hostname,"list")
 if not fnames then return false end
 local rt = {}
 for k,v in pairs(fnames) do
  fv = v:match(filter)
  if fv then
   rt[fv] = function(...)
    return rpc.call(hostname,v,...)
   end
  end
 end
 return rt
end

local function setacl(self, fname, host)
 self[fname] = self[fname] or {}
 self[fname][host] = true
end
rpc.allow = setmetatable({},{__call=setacl})
rpc.deny = setmetatable({},{__call=setacl})

local function isPermitted(host,fn)
 if rpc.allow[fn] then
  return rpc.allow[fn][host] or false
 end
 if rpc.deny[fn] and rpc.deny[fn][host] then
  return false
 end
 return true
end

function rpc.register(name,fn)
 if not rpcrunning then
  event.listen("net_msg",function(_, from, port, data)
   if port == rpc.port then
    local rpcrq = serial.unserialize(data)
    if rpcf[rpcrq[1]] and isPermitted(from,rpcrq[1]) then
     local rt = {pcall(rpcf[rpcrq[1]],table.unpack(rpcrq))}
     minitel.send(from,port,serial.serialize({rpcrq[2],pcall(rpcf[rpcrq[1]],table.unpack(rpcrq,3))}))
    elseif type(rpcrq[2]) == "string" then
     minitel.send(from,port,serial.serialize({rpcrq[2],false,"function unavailable"}))
    end
   end
  end)
  function rpcf.list()
   local rt = {}
   for k,v in pairs(rpcf) do
    rt[#rt+1] = k
   end
   return rt
  end
  rpcrunning = true
 end
 rpcf[name] = fn
end

return rpc
