fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '1.1.5' 
description 'Redeem System'
author 'Midnight Chronicles'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/init.lua',
}

files {
    'locales/*.json'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

client_scripts {
    'client/*.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'community_bridge'
}