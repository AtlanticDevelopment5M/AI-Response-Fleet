fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'AI Response Fleet'
author 'Atlantic Development'
version '1.0.0'
description 'Unified Tow + Transport + Coroner with shared config & helpers'

shared_scripts {
  'config.lua',
  'utils.lua'
}

client_scripts {
  'client/coroner_client.lua',
  'client/transport_client.lua',
  'client/tow_client.lua',
  'client/blips.lua'
}

server_scripts {
  'server/main.lua'
}

dependencies {
  -- optional: 'ox_target'
}

