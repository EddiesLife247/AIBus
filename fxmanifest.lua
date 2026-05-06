-- qb-aibus/fxmanifest.lua
fx_version 'cerulean'
game 'gta5'

author 'EddiesLife247'
description 'AI Bus Driver Script for QBX, Ox_Lib, Ox_inventory & Renewed Banking'
version '1.0.0'

shared_script {
'config.lua',
'lang.lua',
}

escrow_ignore {
'config.lua',
'lang.lua',
}

client_scripts {
'client/main.lua'
}

server_scripts {
'server/main.lua'
}

dependencies {
'qb-core',
'ox_target',
'ox_inventory',
-- 'Renewed-Banking'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

lua54 'yes'