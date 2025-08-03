# 🎁 Midnight Redeem System

A **simple and flexible redeem system** designed for one-off giveaways, player refunds, or event-based rewards. This system leverages input dialogs for a seamless user experience.

Easily customizable and highly adaptable, Midnight Redeem System supports various frameworks, inventory systems, notifications, and menus through its **Community Bridge** integration.

---

## ✨ Features

### 🔐 **Code Restrictions**  
Implement usage limits for your redeem codes. Each code can be configured for a specific number of uses, and critically, each player can redeem a code **only once**, ensuring fairness and preventing abuse.

### 📆 **Expiry System (SQL-based)**  
Define the active lifespan of your redeem codes. Expiration is managed in **real-time** directly through your SQL database, providing precise control over code availability.

### 🎒 **Custom Rewards**  
Offer a diverse range of rewards to your players:
- 🎁 **Item Rewards:** Distribute in-game items with specified quantities (`item`, `amount`).
- 💵 **Money Rewards:** Grant in-game currency, with options for cash or bank deposits (`money`, `amount`, `option`).
- 🚗 **Vehicle Rewards:** Provide players with specific vehicles (`vehicle`, `model`).
- **Combined Rewards:** Create complex reward codes that combine multiple reward types simultaneously.

### ⚙️ **Bridge Integration**  
Fully compatible with [Community Bridge](https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge), offering extensive flexibility:
- **Notification Systems:** Integrate with your preferred notification system.
- **Input Dialogs/Menus:** Utilize any input dialog or menu system for player interactions.
- **Inventory Systems:** Seamlessly connect with your existing inventory management.
- **Framework Agnostic:** Adaptable to your preferred server framework.

---

## 🔧 Dependencies

[Community Bridge](https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge)

**Ensure these resources are started `before` `midnight_redeem`:**
```
ensure ox_lib
ensure your_core          # Replace with your core resource (e.g., es_extended, qb-core)
ensure your_inventory     # Replace with your inventory resource (e.g., ox_inventory, qb-inventory)
ensure community_bridge
ensure midnight_redeem
```

### Player Command
`/redeemcode` (changeable in config)  
Prompts the player to input their redeem code.

### Admin Command
`/genredeem` (changeable in config)  
Opens an input dialog for administrators to generate new redeem codes with comprehensive reward configurations.

---

## 🧩 Reward Fields Explained
When creating a reward code, configure these fields to define its properties and rewards:

| Field         | Description                                        | Example                           |
| :------------ | :------------------------------------------------- | :-------------------------------- |
| `item`        | The name of the inventory item to be given.        | `"water"`, `"repair_kit"`         |
| `amount`      | The quantity of the item or money to be granted.   | `5`, `1000`                       |
| `money`       | Set to `true` if this reward is in-game currency.  | `"money": true`                   |
| `option`      | Specifies the money type: `"cash"` or `"bank"`.    | `"option": "cash"`                |
| `vehicle`     | Set to `true` if this reward is a vehicle.         | `"vehicle": true`                 |
| `model`       | The model name of the vehicle to be spawned.       | `"model": "adder"`                |
| `uses`        | The maximum number of times the code can be used in total. | `"3"`                     |
| `days`        | The number of days the code remains valid from creation. | `"7"`                     |
| `custom code` | The actual string or code that players will enter to redeem. | `"GIFT2025"`              |

---

## 📄 Usage Examples

### Basic Example
This example demonstrates generating a redeem code with items, money, and a vehicle reward, limited to 3 uses and valid for 7 days.

```lua
exports['midnight_redeem']:GenerateRedeemCode(
    source,
    '[{"item":"bread","amount":5},{"money":true,"amount":1000,"option":"cash"},{"vehicle":true,"model":"adder"}]',
    "3",        -- Max uses
    "7",        -- Expiry in days
    "GIFT2025"  -- Custom code
)
```

### Dynamic From User Input
This example illustrates how to dynamically generate a redeem code based on user-provided inputs, such as player ID, reward structure, uses, expiry, and the custom code itself.

```lua
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
```
## zdiscord integration

```
go to 'zdiscord_command_file' and copy generateredeem.js file
go to zdicord/server/commands and paste the file into the folder
make sure zdiscord is started after midnight_redeem
restart server
good to go :)
```