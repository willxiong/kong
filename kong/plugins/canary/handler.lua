-- Copyright (C) Kong Inc.

local BasePlugin = require "kong.plugins.base_plugin"

local math_random = math.random
local math_floor = math.floor
local math_fmod = math.fmod
local crc32 = ngx.crc32_short

local log_prefix = "[canary] "

local Canary = BasePlugin:extend()

function Canary:new()
  Canary.super.new(self, "canary")
end

local function get_hash(hash)
  local ctx = ngx.ctx
  local identifier

  if hash == "consumer" then
    -- Consumer is identified id
    identifier = ctx.authenticated_consumer and ctx.authenticated_consumer.id
    if not identifier and ctx.authenticated_credential then
      -- Fallback on credential
      identifier = ctx.authenticated_credential.id
    end
  end

  if not identifier then
    -- remote IP
    identifier = ngx.var.remote_addr
    if not identifier then
      -- Fallback on a random number
      identifier = tostring(math_random())
    end
  end

  return crc32(identifier)
end

local function switch_target(conf)
  -- switch upstream host to the new hostname
  if conf.target_host then
    ngx.ctx.balancer_address.host = conf.target_host
  end
  -- switch upstream uri to the new uri
  if conf.target_uri then
    ngx.var.target_uri = conf.target_uri
  end
end

local conf_cache = setmetatable({},{__mode = "k"})

function Canary:access(conf)
  Canary.super.access(self)
  
  local percentage, start, steps, duration = conf.percentage, conf.start, conf.steps, conf.duration
  local time = ngx.now()

  local step
  local run_conf = conf_cache[conf]
  if not run_conf then
    run_conf = {}
    conf_cache[conf] = run_conf
    run_conf.prefix = log_prefix .. ngx.ctx.balancer_address.host ..
       "->" .. conf.target_host .. " "
    run_conf.step = -1
  end

  if percentage then
    -- fixed percentage canary
    step = percentage * steps / 100

  else
    -- timer based canary
    if time < start then
      -- not started yet, exit
      return
    end

    if time > start + duration then
      -- completely done, switch target
      switch_target(conf)
      return
    end

    -- calculate current step, and hash position. Both 0-indexed.
    step = math_floor((time - start) / duration * steps)
  end

  local hash = math_fmod(get_hash(conf.hash), steps)

  if step ~= run_conf.step then
    run_conf.step = step
    ngx.log(ngx.DEBUG, run_conf.prefix, step, "/", conf.steps)
  end

  if hash <= step then
    switch_target(conf)
  end
end

Canary.PRIORITY = 13

return Canary
