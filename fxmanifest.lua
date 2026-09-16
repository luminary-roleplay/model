fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
games { 'rdr3', 'gta5' }
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'tm_model'
author 'Kode Red'
description 'Standalone synced model library'
version '1.0.0'
license 'LGPL-3.0-or-later'
repository 'https://github.com/Twilight-Moon-LLC/tm_model'
description 'A standalone model library for client-synced data management in FiveM and RedM. Provides a simple API for defining models, syncing data between server and clients, and subscribing to updates.'


dependencies {
    'ox_lib',
}

server_scripts {
    '@ox_lib/init.lua',
    'server/registry.lua',
    'server/paging.lua',
}

files {
    'shared/**/*.lua',
    'client/**/*.lua',
}