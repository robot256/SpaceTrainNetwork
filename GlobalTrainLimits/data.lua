
flib = require('__flib__.data-util')

local GLOBAL_NAME = "global-train-stop"
local PROXY_NAME = "proxy-train-stop"


-- Make the Global Train Stop and the Proxy Train Stop

local proxy_stop = flib.copy_prototype(data.raw["train-stop"]["train-stop"], PROXY_NAME)
local proxy_item = flib.copy_prototype(data.raw["item"]["train-stop"], PROXY_NAME)
proxy_item.order = proxy_item.order.."y"
local icon_overlay = { { icon = "__base__/graphics/icons/signal/signal_P.png", icon_size = 64, scale = 0.14, shift = {20,20} } }
proxy_item.icons = flib.create_icons(proxy_item,icon_overlay) or icon_overlay

local proxy_recipe = flib.copy_prototype(data.raw["recipe"]["train-stop"], PROXY_NAME)
data:extend{proxy_stop, proxy_item, proxy_recipe}

local global_stop = flib.copy_prototype(data.raw["train-stop"]["train-stop"], GLOBAL_NAME)
local global_item = flib.copy_prototype(data.raw["item"]["train-stop"], GLOBAL_NAME)
global_item.order = global_item.order.."x"
icon_overlay = { { icon = "__base__/graphics/icons/signal/signal_G.png", icon_size = 64, scale = 0.14, shift = {20,20} } }
global_item.icons = flib.create_icons(global_item,icon_overlay) or icon_overlay
local global_recipe = flib.copy_prototype(data.raw["recipe"]["train-stop"], GLOBAL_NAME)
data:extend{global_stop, global_item, global_recipe}


table.insert( data.raw["technology"]["automated-rail-transportation"].effects,
    { type = "unlock-recipe", recipe = GLOBAL_NAME} )
table.insert( data.raw["technology"]["automated-rail-transportation"].effects,
    { type = "unlock-recipe", recipe = PROXY_NAME} )

flib = nil
