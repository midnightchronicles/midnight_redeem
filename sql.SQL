CREATE TABLE `redeem_codes` (
    `code` VARCHAR(60) NOT NULL COLLATE 'utf8mb3_general_ci',
    `total_item_count` INT NOT NULL,
    `items` JSON NOT NULL,
    `uses` INT NOT NULL,
    `created_by` VARCHAR(255) NOT NULL COLLATE 'utf8mb3_general_ci',
    `expiry` DATETIME NULL DEFAULT NULL,
    `redeemed_by` JSON NULL DEFAULT (JSON_OBJECT()),
    PRIMARY KEY (`code`),
    CONSTRAINT `redeemed_by_valid` CHECK (JSON_VALID(`redeemed_by`))
) ENGINE=InnoDB
DEFAULT CHARSET=utf8mb3
COLLATE=utf8mb3_general_ci;