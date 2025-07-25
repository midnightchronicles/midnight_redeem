fx_version 'cerulean'
game 'gta5'
lua54 "yes"
version '1.0.6'

description 'Redeem System'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server.lua'
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client.lua'
}

dependencies {
'community_bridge'
}
