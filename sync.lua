require "ip_blacklist/config"

local function sync()
    ngx.log(ngx.DEBUG, "Begin of update blacklist")

    local ip_blacklist = ngx.shared.ip_blacklist
    local redis = require "resty.redis"
    local red = redis:new()

    red:set_timeout(redis_connect_timeout)

    -- 连接redis
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection error while retrieving ip_blacklist: " .. err)
        return
    end

    -- 获取新黑名单到本地缓存
    local new_ip_blacklist, err = red:smembers(redis_key)
    if err then
        ngx.log(ngx.ERR, "Redis read error while retrieving ip_blacklist: " .. err)
        return
    end
    -- TODO: 是否能一次覆盖所有
    ip_blacklist:flush_all()
    for index, banned_ip in ipairs(new_ip_blacklist) do
        ip_blacklist:set(banned_ip, true)
    end

    ngx.log(ngx.DEBUG, "End of update blacklist")
    return
end

local function handler(premature)
    if not premature then
        sync()
        local ok, err = ngx.timer.at(sync_interval, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

-- 同步黑名单定时任务
function sync_loop()
    if 0 == ngx.worker.id() then
        local ok, err = ngx.timer.at(sync_interval, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
        ngx.log(ngx.INFO, "Sync loop start")
    end
end

sync_loop()
