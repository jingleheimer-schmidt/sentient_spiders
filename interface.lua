
-- This file contains the interface functions for the mod.
-- The "ignore_spider" interface may be used to add a spidertron to the list of ignored spiders, so that this mod will not send it wandering.

-- usage: remote.call("sentient-spiders", "ignore_spider", "name of spider prototype to ignore")

---@param name string
local function ignore_spider(name)
    storage.ignored_spidertrons = storage.ignored_spidertrons or {}
    storage.ignored_spidertrons[name] = true
end

local interface_functions = {
    ignore_spider = ignore_spider,
}

remote.add_interface("sentient-spiders", interface_functions)
