function NotificationUser(_, description, type)
    Bridge.Notify.SendNotify(description, type, 6000)
end

RegisterNetEvent("midnight-redeem:notifyUser", function(title, description, type)
    NotificationUser(title, description, type)
end)

RegisterNetEvent("midnight-redeem:openAdminMenu", function()
    RegisterCodeMenus()
end)

RegisterNetEvent("midnight-redeem:redeemcode", function()
    RegisterRedeemMenu()
end)
