
flib = require('__flib__.data-util')

-- Make the Global Train Stop and the Proxy Train Stop

local proxy_stop = flib.copy_prototype(data.raw["train-stop"]["train-stop"], "proxy-train-stop")
local proxy_item = flib.copy_prototype(data.raw["item"]["train-stop"], "proxy-train-stop")
proxy_item.order = proxy_item.order.."y"
local proxy_recipe = flib.copy_prototype(data.raw["recipe"]["train-stop"], "proxy-train-stop")
data:extend{proxy_stop, proxy_item, proxy_recipe}

local global_stop = flib.copy_prototype(data.raw["train-stop"]["train-stop"], "global-train-stop")
local global_item = flib.copy_prototype(data.raw["item"]["train-stop"], "global-train-stop")
global_item.order = global_item.order.."x"
local global_recipe = flib.copy_prototype(data.raw["recipe"]["train-stop"], "global-train-stop")
data:extend{global_stop, global_item, global_recipe}


table.insert( data.raw["technology"]["automated-rail-transportation"].effects,
    { type = "unlock-recipe", recipe = "global-train-stop"} )
table.insert( data.raw["technology"]["automated-rail-transportation"].effects,
    { type = "unlock-recipe", recipe = "proxy-train-stop"} )

flib = nil
