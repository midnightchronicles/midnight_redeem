fx_version 'cerulean'
game 'gta5'
lua54 'yes'

ui_page 'html/index.html'

version '2.0.0'
description 'Redeem System'
author 'Midnight Chronicles'

files {
    'html/**',
    'locales/*.json'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/permissions.lua',
    'server/admin_check.lua',
    'server/runtime_config.lua',
    'server/version_check.lua',
    'server/main.lua',
    'server/shadow_ai.lua'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/init.lua'
}

client_scripts {
    'client/*.lua'
}

escrow_ignore {
    'server/permissions.lua',
    'server/admin_check.lua',
    'server/runtime_config.lua',
    'server/version_check.lua',
    'shared/init.lua',
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'community_bridge'
}
