module.exports = {
    name: "generateredeem",
    description: "Generate a redeem code for items, money, and vehicles.",
    role: "mod",

    options: [
        {
            name: "uses",
            description: "How many times the code can be redeemed.",
            required: true,
            type: "INTEGER",
        },
        {
            name: "expiry",
            description: "Days until code expires.",
            required: true,
            type: "INTEGER",
        },
        {
            name: "customcode",
            description: "Custom code (must be unique).",
            required: true,
            type: "STRING",
        },
        {
            name: "itemnames",
            description: "Comma-separated item names (e.g. water,bread).",
            required: false,
            type: "STRING",
        },
        {
            name: "itemamounts",
            description: "Comma-separated item amounts (e.g. 2,3, must match item names).",
            required: false,
            type: "STRING",
        },
        ...Array.from({ length: 0 }, (_, i) => ([
            {
                name: `itemname${i + 1}`,
                description: `Extra item #${i + 1} name (optional).`,
                required: false,
                type: "STRING",
            },
            {
                name: `itemamount${i + 1}`,
                description: `Extra item #${i + 1} amount (optional).`,
                required: false,
                type: "INTEGER",
            }
        ])).flat(),
        {
            name: "vehicle",
            description: "Vehicle spawn name to grant (optional).",
            required: false,
            type: "STRING",
        },
        {
            name: "moneyamount",
            description: "Amount of money to grant (optional).",
            required: false,
            type: "INTEGER",
        },
        {
            name: "peruserlimit",
            description: "Times each player can redeem (0 for unlimited).",
            required: false,
            type: "INTEGER",
        },
    ],

    run: async (client, interaction, args) => {
        let rewards = [];

        for (let i = 1; i <= 10; i++) {
            const itemName = args[`itemname${i}`];
            const itemAmount = args[`itemamount${i}`];
            const parsedAmount = parseInt(itemAmount, 10);
            if (itemName && !Number.isNaN(parsedAmount) && parsedAmount > 0) {
                rewards.push({ item: itemName.trim(), amount: parsedAmount });
            }
        }

        if (rewards.length === 0 && args.itemnames && args.itemamounts) {
            const items = args.itemnames.split(",");
            const amounts = args.itemamounts.split(",");
            if (items.length !== amounts.length) {
                return interaction.reply({
                    content: "Number of item names and amounts must match.",
                    ephemeral: true,
                });
            }
            for (let i = 0; i < items.length; i++) {
                const item = items[i].trim();
                const amount = parseInt(amounts[i].trim(), 10);
                if (item && !Number.isNaN(amount) && amount > 0) {
                    rewards.push({ item, amount });
                }
            }
        }

        if (args.moneyamount) {
            const moneyAmount = parseInt(args.moneyamount, 10);
            if (!Number.isNaN(moneyAmount) && moneyAmount > 0) {
                rewards.push({ money: true, amount: moneyAmount, option: "cash" });
            }
        }

        if (args.vehicle && args.vehicle.trim() !== "") {
            rewards.push({ vehicle: true, model: args.vehicle.trim() });
        }

        if (rewards.length === 0) {
            return interaction.reply({
                content: "You must specify at least one item, money amount, or vehicle.",
                ephemeral: true,
            });
        }
        const uses = parseInt(args.uses, 10);
        const expiryDays = parseInt(args.expiry, 10);
        const perUserRaw = args.peruserlimit !== undefined ? parseInt(args.peruserlimit, 10) : 1;
        const perUserLimit = !Number.isNaN(perUserRaw) && perUserRaw >= 0 ? perUserRaw : 1;
        const customCode = (args.customcode || "").trim();

        if (Number.isNaN(uses) || uses <= 0 || Number.isNaN(expiryDays) || !customCode) {
            return interaction.reply({
                content: "Invalid uses, expiry, or code.",
                ephemeral: true,
            });
        }

        const itemsJson = JSON.stringify(rewards);
        emit("zdiscord:generateRedeemCode", itemsJson, uses, expiryDays, customCode, perUserLimit);

        let description = `✅ Your redeem code: \`${customCode}\`\n`;
        for (const reward of rewards) {
            if (reward.item) {
                description += `📦 Item: **${reward.item}**\n⚙️ Amount: **${reward.amount}**\n`;
            }
            if (reward.money) {
                description += `💰 Money: **${reward.amount}**\n`;
            }
            if (reward.vehicle) {
                description += `🚗 Vehicle: **${reward.model}**\n`;
            }
        }
        const expiryLine = expiryDays > 0 ? `${expiryDays} days` : "No expiry";
        const perUserLine = perUserLimit === 0 ? "Unlimited" : perUserLimit;
        description += `♻️ Uses: **${uses}**\n👤 Per user: **${perUserLine}**\n📅 Expires in: **${expiryLine}**`;

        return interaction.reply({
            embeds: [{
                color: 0x00ff99,
                description: description
            }],
            ephemeral: false,
        });
    },
};