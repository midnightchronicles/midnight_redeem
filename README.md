this is a basic redeem system utilising input dialog which i find useful for things like giving refunds or one of quick giveaways

* limit the uses of how many times the code can be used only allowing players to use the code once making it fair on others
* set the days of how long the code will be available in real time via sql
* you can choose item and amount or you can choose how much cash and or you can do both if your feeling generous (planned to do option for cash or card soon)

with the bridge that is utilised within this script gives alot of options for different
input dialogs, notifications, frameworks, inventorys making it easy to customise to whatever resource you use without being limited

# dependancys

* https://github.com/overextended/ox_lib/releases (if using ox_lib menu)
* https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge/releases - community bridge

# item name:
the item name in your inventory i.e water or advanced_reparkit
# item amount:
how many of the items would you like to give
# money amount:
how much cash would you like to give
# uses: 
how many times the code can be used
# days: 
how many days you want the code to last for this will be saved to the sql
# custom code:
the code you want the player to use when doing the /redeemcode command

# Very simple command
/genredeem
/redeemcode

# instructions

download dependancy and make sure they are started before midnight_redeem below is a recommended started

ensure ox_lib
ensure your_core
ensure your_inventory
ensure community_bridge
ensure midnight_redeem

# exports

--server
exports['midnight_redeem']:GenerateRedeemCode()

examples

exports['midnight_redeem']:GenerateRedeemCode(
    source,
    '[{"item":"bread","amount":5},{"money":true,"amount":1000,"option":"cash"},{"vehicle":true,"model":"adder"}]',
    "3",                -- Max uses
    "7",                -- Expiry in days
    "GIFT2025"          -- Custom code
)

or

local playerId = source
local code = userProvidedCode
local uses = tostring(userProvidedUses)
local expiry = tostring(userProvidedDays)
local rewardsJson = json.encode(userProvidedRewards)

exports['midnight_redeem']:GenerateRedeemCode(
    playerId,
    rewardsJson,
    uses,
    expiry,
    code
)

these are just examples please do not use there is no support regarding the export use only do this if you know what your doing
