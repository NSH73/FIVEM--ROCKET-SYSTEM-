fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rocket-airstrike'
author 'ROCKET-SYSTEM'
description 'QBCore aircraft orbital camera and airstrike system'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'qb-core'
}
