require "ip_blacklist.config"

local function load_file(path)
    ngx.log(ngx.DEBUG, "Load data by file: " .. path)
    local res = {}
    local file = io.open(path, "r")
    local index = 1

    for line in file:lines() do
        res[index] = line
        index = index + 1
    end

    file:close()
    return res
end

local function dump_file(path, array)
    ngx.log(ngx.DEBUG, "Dump data into file: " .. path)
    local file = io.open(path, "w+")
    for _, key in ipairs(array) do
        file:write(key .. "\n")
    end
    file:close()
end

local function sync()
    ngx.log(ngx.DEBUG, "Begin of update blacklist")

    local ip_blacklist = ngx.shared.ip_blacklist
    local redis = require "resty.redis"
    local red = redis:new()
    local new_ip_blacklist = {}
    local new_ip_blacklist_expireat = {}

    red:set_timeout(redis_connect_timeout)

    -- 连接redis
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection error while retrieving ip_blacklist: " .. err)
        new_ip_blacklist = load_file(cache_file)
        new_ip_blacklist_expireat = load_file(expireat_cache_file)
    else
        -- 获取新黑名单到nginx缓存
        new_ip_blacklist, err = red:keys(redis_key_prefix .. "*")
        if err then
            ngx.log(ngx.ERR, "Redis read error while retrieving ip_blacklist: " .. err)
            new_ip_blacklist = load_file(cache_file)
            new_ip_blacklist_expireat = load_file(expireat_cache_file)
        end

        if new_ip_blacklist[1] ~= nil then
            new_ip_blacklist_expireat, err = red:mget(unpack(new_ip_blacklist))
            if err then
                ngx.log(ngx.ERR, "Redis read error while retrieving ip_blacklist: " .. err)
                new_ip_blacklist = load_file(cache_file)
                new_ip_blacklist_expireat = load_file(expireat_cache_file)
            end
        end
    end

    -- TODO: 是否能一次覆盖所有
    ngx.log(ngx.DEBUG, "Flush blacklist")
    ip_blacklist:flush_all()
    for index, key in ipairs(new_ip_blacklist) do
        local ext = new_ip_blacklist_expireat[index]
        if not ext then
            ngx.log(ngx.WARN, "The IP expired: " .. ip)
        else
            local _, ip = string.match(key, "(.*)_(.*)")
            if "0" == ext then
                ngx.log(ngx.DEBUG, "Set IP: " .. ip .. ", expire: 0")
                ip_blacklist:set(ip, 1)
            else
                local ex = ext - math.floor(ngx.now())
                if ex <= 0 then
                    ngx.log(ngx.WARN, "The IP expired: " .. ip)
                else
                    ngx.log(ngx.DEBUG, "Set IP: " .. ip .. ", expire: " .. ex)
                    ip_blacklist:set(ip, 1, ex)
                end
            end
        end
    end

    -- 缓存到本地文件
    dump_file(cache_file, new_ip_blacklist)
    dump_file(expireat_cache_file, new_ip_blacklist_expireat)

    -- keppalive
    local ok, err = red:set_keepalive(sync_interval * 2 * 1000, 100)
    if not ok then
        ngx.log(ngx.ERR, "Redis failed to set keepalive: ", err)
        local ok, err = red:close()
        if not ok then
            ngx.log(ngx.ERR, "Redis failed to close: ", err)
        end
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
        ngx.timer.at(0, sync)
        local ok, err = ngx.timer.at(sync_interval, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
        ngx.log(ngx.INFO, "Sync loop start")
    end
end

sync_loop()
