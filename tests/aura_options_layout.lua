-- Run from the repository root: lua5.1 tests/aura_options_layout.lua
-- Schema/callback regression test; not a replacement for a WoW client test.
local function copy(value)
	if type(value) ~= 'table' then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end

local helper = {}
local auraModule = { BuffFrame = {}, DebuffFrame = {}, updates = 0 }
function auraModule:UpdateHeader() self.updates = self.updates + 1 end
function auraModule:UpdateAllAuras() self.updates = self.updates + 1 end

local defaults = {
	buffs = { priority = 'Default', barColor = { r = 1, g = 1, b = 1, a = 1 } },
	debuffs = { priority = 'Default', barColor = { r = 1, g = 1, b = 1, a = 1 } }
}
local engine = {
	Options = { args = {} },
	Config = { { Values = { GrowthDirection = {}, FontSize = {} } }, setmetatable({}, { __index = function(_, key) return key end }) },
	Libs = { ACH = helper, AceConfigDialog = {}, AceConfigRegistry = { NotifyChange = function() end } },
	private = { auras = { enable = true, buffsHeader = true, debuffsHeader = true } },
	db = { auras = copy(defaults) },
	noop = function() end
}
function engine:GetModule(name)
	assert(name == 'Auras')
	return auraModule
end
local stub = {}
function stub:NewLibrary() return helper end
setmetatable(stub, { __call = function() return {} end })
local env = setmetatable({
	LibStub = stub,
	ElvUI = { engine, {}, {}, { auras = defaults }, {} },
	CopyTable = copy,
	DebuffTypeColor = { Magic = {}, Curse = {}, Disease = {}, Poison = {}, none = {} },
	GetCVar = function() return '1' end
}, { __index = _G })
env._G = env
local function load(path)
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk()
end
load('ElvUI_Libraries/Core/LibAceConfigHelper/LibAceConfigHelper.lua')
load('ElvUI_Options/Core/Auras.lua')

local auras = engine.Options.args.auras
local function isInline(option)
	if option.dialogInline ~= nil then return option.dialogInline end
	if option.guiInline ~= nil then return option.guiInline end
	return option.inline
end
local function hasPages(group)
	for _, option in pairs(group.args) do
		if option.type == 'group' and not isInline(option) then return true end
	end
	return false
end
local function checkLayout(group)
	if hasPages(group) then
		for _, option in pairs(group.args) do
			assert(option.type == 'group' and not isInline(option), 'controls must not compete with a fill-height selector')
		end
	end
	for _, option in pairs(group.args) do
		if option.type == 'group' and not isInline(option) then checkLayout(option) end
	end
end
checkLayout(auras)
local function countControls(group)
	local total = 0
	for _, option in pairs(group.args) do
		total = total + (option.type == 'group' and countControls(option) or 1)
	end
	return total
end
assert(countControls(auras) == 96, 'existing aura controls must not be dropped')
assert(auras.childGroups == 'tab')
for _, group in ipairs({ auras, auras.args.buffs, auras.args.debuffs }) do
	assert(group.args.general and not hasPages(group.args.general), 'General must be a scrollable leaf page')
	for key, option in pairs(group.args) do
		if key ~= 'general' then assert(option.order > group.args.general.order, 'General must be selected first') end
	end
end

-- Root settings retain their inherited private-data handlers.
local enable = { 'auras', 'general', 'enable' }
assert(auras.get(enable))
auras.set(enable, false)
assert(engine.private.auras.enable == false and engine.ShowPopup)
assert(auras.args.general.args.debuffColors.inline)
assert(auras.args.general.args.colorGroup.get)
assert(auras.args.masqueGroup.args.masque)

for _, auraType in ipairs({ 'buffs', 'debuffs' }) do
	local group = auras.args[auraType]
	local common = group.args.general.args
	assert(common.size and common.height and common.wrapAfter and common.growthDirection)
	assert(common.filtersGroup.guiInline and common.filtersGroup.args.filterPriority.dragdrop)
	-- Keep non-inline subgroup paths: notBarShow indexes info[#info - 2].
	assert(group.args.statusBar and group.args.timeGroup and group.args.countGroup)
	local sizeInfo = { 'auras', auraType, 'general', 'size' }
	group.set(sizeInfo, 31)
	assert(group.get(sizeInfo) == 31 and engine.db.auras[auraType].size == 31)
	common.keepSizeRatio.set(nil, false)
	assert(engine.db.auras[auraType].height == 31)
	assert(not common.height.hidden())
	local barInfo = { 'auras', auraType, 'statusBar', 'barTexture' }
	engine.db.auras[auraType].barShow = false
	assert(group.args.statusBar.args.barTexture.disabled(barInfo))
	engine.db.auras[auraType].barShow = true
	assert(not group.args.statusBar.args.barTexture.disabled(barInfo))
	group.args.statusBar.args.barColor.set(nil, 0.1, 0.2, 0.3)
	assert(engine.db.auras[auraType].barColor.g == 0.2)
	assert(common.filtersGroup.args.filter.get == engine.noop)
end
assert(auras.args.buffs.args.consolidateGroup)
assert(not auras.args.debuffs.args.consolidateGroup)
assert(auraModule.updates == 4)
print('PASS: aura schema uses leaf pages; inherited handlers, filter controls and subgroup paths preserved')
