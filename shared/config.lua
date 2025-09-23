Config = {}

Config.Debug = true

----------------------------------------core settings--------------------------------------------------------------------------------
Config.Framework = 'qb'

----------------------------------------general options------------------------------------------------------------------------------
Config.AdminCommand = "adminredeem" -- admin menu
Config.RedeemCommand = "redeemcode" -- user redeeem command
Config.mincustomchar = 8 -- minimum character length for custom code set to false or 0 if you want to disable

----------------------------------------daily rewards--------------------------------------------------------------------------------
Config.DailyRewardEnabled      = true          -- toggle on/off
Config.DailyRewarduses         = 10            -- total global uses (number)
Config.DailyRewardperuserlimit = 1             -- per-user uses; 0 = unlimited (number)
Config.DailyRewardhours        = 6             -- expires this many hours from creation (number) -- recommended to do between server restarts i.e server restarts every 6 hours do 6 hour expiry

return Config