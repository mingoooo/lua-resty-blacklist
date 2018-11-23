require "ip_blacklist/config"
local cjson = require "cjson"
local redis = require "resty.redis"

local red = redis:new()
red:set_timeout(redis_connect_timeout)
local ok, err = red:connect(redis_host, redis_port)
if not ok then
    local reason = "Redis connection error while retrieving ip_blacklist: " .. err
    ngx.log(ngx.ERR, reason)
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = {}, reason = reason}))
    ngx.exit(ngx.HTTP_OK)
end

local function keepalive()
    local ok, err = red:set_keepalive(60000, 50)
    if not ok then
        ngx.log(ngx.ERR, "Redis failed to set keepalive: ", err)
        local ok, err = red:close()
        if not ok then
            ngx.log(ngx.ERR, "Redis failed to close: ", err)
        end
    end
end

local function get()
    local data = {}
    local ip_blacklist, err = red:keys(redis_key_prefix .. "*")
    if err then
        local reason = "Redis read error while retrieving ip_blacklist: " .. err
        ngx.log(ngx.ERR, reason)
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        cjson.encode_empty_table_as_object(false)
        ngx.say(cjson.encode({data = {}, reason = reason}))
        return
    end

    for _, key in ipairs(ip_blacklist) do
        local _, ip, ext = string.match(key, "(.*)_(.*)_(.*)")
        table.insert(data, {ip = ip, expireat = tonumber(ext)})
    end

    ngx.say(cjson.encode({data = data, reason = ""}))
    return
end

local function post()
end

local function put()
end

local method_name = ngx.req.get_method()
if method_name == "GET" then
    get()
elseif method_name == "POST" then
    post()
elseif method_name == "PUT" then
    put()
else
    ngx.status = ngx.HTTP_BAD_REQUEST
    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = {}, reason = "Unknown method: " .. method_name}))
end
keepalive()
ngx.exit(ngx.HTTP_OK)
