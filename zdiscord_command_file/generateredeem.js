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
],

    run: async (client, interaction, args) => {
        let rewards = [];

        if (args.itemnames && args.itemamounts) {
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
                const amount = parseInt(amounts[i].trim());
                if (item && !isNaN(amount) && amount > 0) {
                    rewards.push({ item: item, amount: amount });
                }
            }
        }

        if (args.moneyamount && parseInt(args.moneyamount) > 0) {
            rewards.push({ money: true, amount: parseInt(args.moneyamount) });
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
        if (isNaN(args.uses) || isNaN(args.expiry) || !args.customcode) {
            return interaction.reply({
                content: "Invalid uses, expiry, or code.",
                ephemeral: true,
            });
        }

        const itemsJson = JSON.stringify(rewards);
        const uses = parseInt(args.uses);
        const expiryDays = parseInt(args.expiry);
        const customCode = args.customcode;

        emit("zdiscord:generateRedeemCode", itemsJson, uses, expiryDays, customCode);

        let description = `✅ Your redeem code: \`${customCode}\`\n`;
        for (const reward of rewards) {
            if (reward.item) {
                description += `📦 Item: **${reward.item}**\n🔢 Amount: **${reward.amount}**\n`;
            }
            if (reward.money) {
                description += `💰 Money: **${reward.amount}**\n`;
            }
            if (reward.vehicle) {
                description += `🚗 Vehicle: **${reward.model}**\n`;
            }
        }
        description += `♻️ Uses: **${uses}**\n📅 Expires in: **${expiryDays} days**`;

        return interaction.reply({
            embeds: [{
                color: 0x00ff99,
                description: description
            }],
            ephemeral: false,
        });
    },
};
