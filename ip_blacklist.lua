-- a quick LUA access script for nginx to check IP addresses against an
-- `ip_blacklist` set in Redis, and if a match is found send a HTTP 403.
--
-- allows for a common blacklist to be shared between a bunch of nginx
-- web servers using a remote redis instance. lookups are cached for a
-- configurable period of time.
--
-- block an ip:
--   redis-cli SET blacklist_127.0.0.1_0 1
-- remove an ip:
--   redis-cli DEL blacklist_127.0.0.1_0 1
--
-- also requires lua-resty-redis from:
--   https://github.com/agentzh/lua-resty-redis
--
-- your nginx http context should contain something similar to the
-- below: (assumes resty/redis.lua exists in /data/svr/openresty/lualib/)
--
--   lua_package_path "/data/svr/openresty/lualib/?.lua;;";
--   lua_shared_dict ip_blacklist 10m;
--   init_worker_by_lua_file /data/svr/openresty/lualib/ip_blacklist/sync.lua;
--
-- you can then use the below (adjust path where necessary) to check
-- against the blacklist in a http, server, location, if context:
--
-- access_by_lua_file /data/svr/openresty/lualib/ip_blacklist/ip_blacklist.lua;
--
-- you can use x_forwarded_for IP
--
-- proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

function get_user_ip()
  local headers = ngx.req.get_headers()
  local ip = ngx.var.http_x_forwarded_for

  if not ip then
    return ngx.var.remote_addr
  end

  local index = ip:find(",")
  if not index then
    return ip
  end

  return ip:sub(1, index - 1)
end

local ip = get_user_ip()
local ip_blacklist = ngx.shared.ip_blacklist

if ip_blacklist:get(ip) then
  ngx.log(ngx.WARN, "Banned IP detected and refused access: " .. ip)
  return ngx.exit(ngx.HTTP_FORBIDDEN)
end
