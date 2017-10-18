local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

return {
  no_consumer = true,
  fields = {
    start = {       -- when to start the release (seconds since epoch)
      type = "number",
    },
    hash = {        -- what element to use for hashing to the target
      type = "string",
      default = "consumer",
      enum = { "consumer", "ip" },
    },
    duration = {    -- how long should the transtion take (seconds)
      type = "number",
      default = 60 * 60  -- 1 hour
    },
    steps = {       -- how many steps
      type = "number",
      default = 1000,
    },
    percentage = {  -- fixed % of traffic, if given overrides start/duration
      type = "number",
    },
    target_host = {  -- target hostname (upstream_url == a, this is b)
      type = "string",
    },
    target_uri = {   -- target uri (upstream_url == a, this is b)
      type = "string",
    },
  },
  self_check = function(schema, conf, dao, is_update)
    -- validate start time
    local time = math.floor(ngx.now())
    if not conf.start then
      conf.start = time
    end
    if conf.start < time then
      return false, Errors.schema "'start' cannot be in the past"
    end

    -- validate duration
    if conf.duration <= 0 then
      return false, Errors.schema "'duration' must be greater than 0"
    end

    -- validate steps
    if conf.steps <= 0 then
      return false, Errors.schema "'steps' must be greater than 0"
    end

    -- validate hostname
    if not utils.check_hostname(conf.target_host) then
      return false, Errors.schema "'target_host' must be a valid hostname"
    end

    if conf.percentage then
      if conf.percentage < 0 or conf.percentage > 100 then
        return false, Errors.schema "'percentage' is invalid"
      end
    end

    if not conf.target_uri and not conf.target_host then
      return false, Errors.schema "either 'target_uri' or 'target_host' must be provided"
    end

    return true
  end,
}
