require "ip_blacklist/config"
local cjson = require "cjson"
local redis = require "resty.redis"

local function say_err(status, reason, log_level)
    if not log_level then
        log_level = ngx.ERR
    end
    ngx.log(log_level, reason)
    ngx.status = status
    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = {}, reason = reason}))
end

local red = redis:new()
red:set_timeout(redis_connect_timeout)
local ok, err = red:connect(redis_host, redis_port)
if not ok then
    local reason = "Redis connection error while retrieving ip_blacklist: " .. err
    say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
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

local function del_pattern(pattern)
    local old_keys, err = red:keys(pattern)
    if err then
        local reason = "Redis read error: " .. err
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return false
    end
    local ok, err = red:multi()
    if not ok then
        ngx.say("Failed to run multi: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return false
    end
    for _, key in ipairs(old_keys) do
        local res, err = red:del(key)
        if err then
            ngx.say("Failed to run del: ", err)
            say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
            return false
        end
    end
    local ans, err = red:exec()
    if err then
        ngx.say("Failed to run exec: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return false
    end
    return true
end

local function del_prekey(ip)
    local pattern = redis_key_prefix .. ip .. "*"
    return del_pattern(pattern)
end

local function get()
    local data = {}
    -- 获取黑名单全部key
    local ip_blacklist, err = red:keys(redis_key_prefix .. "*")
    if err then
        local reason = "Redis read error: " .. err
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
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
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    ngx.log(ngx.DEBUG, "Request body: " .. body)
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        local reason = "Json decode err, please check your request body is array"
        say_err(ngx.HTTP_BAD_REQUEST, reason)
        return
    end

    for _, ip_info in ipairs(data) do
        local ip = ip_info["ip"]
        local expireat = ip_info["expireat"]
        local expire = ip_info["expire"]

        if ip then
            local key
            if expireat then
                expire = expireat - math.floor(ngx.now())
            end

            if expire then
                if not expireat then
                    expireat = math.floor(ngx.now()) + expire
                end
            else
                expire = 0
                expireat = 0
            end

            -- Set key
            key = redis_key_prefix .. ip .. "_" .. expireat
            ngx.log(ngx.DEBUG, "Set redis key: " .. key .. ", expire: " .. expire)
            if expireat == 0 then
                -- 删除旧key
                local ok = del_prekey(ip)
                if not ok then
                    return
                end
                local res, err = red:set(key, 1)
            else
                if expire > 0 then
                    local ok = del_prekey(ip)
                    if not ok then
                        return
                    end
                    local res, err = red:set(key, 1, "EX", expire)
                end
            end
            if err then
                ngx.log(ngx.ERR, "Set redis key err: " .. err)
                ngx.log(ngx.DEBUG, "Set redis key: " .. key .. ", expire: " .. expire)
                say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
                return
            end
        end
    end
end

local function put()
end

local function delete()
end

local method_name = ngx.req.get_method()
if method_name == "GET" then
    get()
elseif method_name == "POST" then
    post()
elseif method_name == "PUT" then
    put()
elseif method_name == "DELETE" then
    delete()
else
    local reason = "Unknown method: " .. method_name
    say_err(ngx.HTTP_BAD_REQUEST, reason, ngx.WARN)
end
keepalive()
ngx.exit(ngx.HTTP_OK)
