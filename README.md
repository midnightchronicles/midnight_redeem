# 🎁 Midnight Redeem System

A **simple, flexible redeem system** using input dialogs – perfect for one-off giveaways, player refunds, or event-based rewards.

Easily customizable with support for various frameworks, inventory systems, notifications, and menus via **Community Bridge**

---

## ✨ Features

## 🔐 **Code Restrictions**  
  Limit how many times a code can be used. Each player can redeem a code **only once**, making it fair for everyone.

## 📆 **Expiry System (SQL-based)**  
  Define how many days a code remains active — expiration is handled in **real time** using your SQL database.

## 🎒 **Custom Rewards**  
  - 🎁 Give items (`item`, `amount`)
  - 💵 Give money (`money`, `amount`)
  - 🚗 Give vehicles (`vehicle`, `model`)
  - Combine multiple reward types in one code

## ⚙️ **Bridge Integration**  
  Fully compatible with [Community Bridge](https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge)
  - Any notification system
  - Any input dialog/menu system
  - Any inventory
  - Your preferred framework

---

## 🔧 Dependencies

[Community Bridge](https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge)

## ensure these resources are started **before** midnight_redeem:   
                                                                                                                                                                                                                                                                                                     
ensure ox_lib                                                                                                                                                    
ensure your_core                                                                                                                                                    
ensure your_inventory                                                                                                                                                    
ensure community_bridge                                                                                                                                                    
ensure midnight_redeem                                                                                                                                                    

## Player Command
/redeemcode (changeable in config)                                                                                                                                                    
Prompts the player to input their redeem code.

## Admin Command
/genredeem (changeable in config)                                                                                                                                                    
Opens an input dialog for an admin to generate a new redeem code with reward configuration.


## 🧩 Reward Fields Explained
When creating a reward code, configure these fields:
| Field         | Description                              | Example                   |
| ------------- | ---------------------------------------- | ------------------------- |
| `item`        | Inventory item name                      | `"water"`, `"repair_kit"` |
| `amount`      | Quantity of item or money                | `5`, `1000`               |
| `money`       | `true` if this is a cash reward          | `"money": true`           |
| `option`      | `"cash"` or `"bank"` for money type      | `"option": "cash"`        |
| `vehicle`     | `true` if giving a vehicle               | `"vehicle": true`         |
| `model`       | Vehicle model to spawn                   | `"model": "adder"`        |
| `uses`        | Max number of uses the code can have     | `"3"`                     |
| `days`        | How many days the code remains valid     | `"7"`                     |
| `custom code` | The actual string/code the player enters | `"GIFT2025"`              |


## Basic Example
exports['midnight_redeem']:GenerateRedeemCode(                                                                                                                                                    
    source,                                                                                                                                                    
    '[{"item":"bread","amount":5},{"money":true,"amount":1000,"option":"cash"},{"vehicle":true,"model":"adder"}]',
    "3",        -- Max uses                                                                                                                                                    
    "7",        -- Expiry in days                                                                                                                                                    
    "GIFT2025"  -- Custom code                                                                                                                                                    
)

## Dynamic From User Input
local playerId = source                                                                                                                                                    
local code = userProvidedCode                                                                                                                                                    
local uses = tostring(userProvidedUses)                                                                                                                                                    
local expiry = tostring(userProvidedDays)                                                                                                                                                    
local rewardsJson = json.encode(userProvidedRewards)                                                                                                                                                    

exports['midnight_redeem']:GenerateRedeemCode(                                                                                                                                                    
    source,         -- player ID                                                                                                                                                    
    rewardsJson,    -- reward structure (items, cash, etc.)                                                                                                                                                    
    uses,           -- max uses                                                                                                                                                    
    expiry,         -- expiry in days                                                                                                                                                    
    code            -- redeem code                                                                                                                                                    
)                                                                                                                                                    

## 
🚀 Happy Redeeming!
This system was built to be lightweight, fair, and easy to customize for whatever your server needs. Have fun, and be generous — or don’t. 😎
