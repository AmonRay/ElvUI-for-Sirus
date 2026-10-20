local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

local function section(source, first, last)
	local startAt = assert(source:find(first, 1, true))
	local endAt = assert(source:find(last, startAt, true))
	return source:sub(startAt, endAt - 1)
end

local function run(source, env)
	local chunk = assert(loadstring(source))
	setfenv(chunk, setmetatable(env, { __index = _G }))
	return chunk()
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

local defaults = { P = {}, CopyTable = copy }
run(section(read("ElvUI/Core/Defaults/Profile.lua"), "P.nameplates = {", "local TopAuras = {"), defaults)
local count = 0
for _, unit in pairs(defaults.P.nameplates.units) do
	if unit.health then
		count = count + 1
		local db = unit.health
		assert(db.absorb.enable == true and db.absorb.showText == false)
		assert(db.absorb.font == db.text.font and db.absorb.fontSize == db.text.fontSize)
		assert(db.absorb.fontOutline == db.text.fontOutline)
	end
end
assert(count == 4)

local function widget()
	return {
		Hide = function(self) self.shown = false end,
		Show = function(self) self.shown = true end,
		SetText = function(self, value) self.value = value end,
		SetWidth = function(self, value) self.width = value end,
		FontTemplate = function(self, ...) self.font = { ... } end,
		SetWordWrap = function() end,
		SetTexture = function() end,
		SetVertexColor = function() end,
		ClearAllPoints = function() end,
		SetPoint = function() end
	}
end

local shield, maximum, apiCalls = 22000, 100000, 0
local health = copy(defaults.P.nameplates.units.ENEMY_PLAYER.health)
local np = { db = { units = { ENEMY_PLAYER = { health = health } } } }
function np:GetHealth() return 50000, maximum end
local env = {
	NP = np,
	E = { media = { blankTex = "blank" }, ShortValue = function(_, amount) return tostring(amount) end },
	LSM = { Fetch = function(_, kind, name) assert(kind == "font") return name end },
	UnitGetTotalAbsorbs = function() apiCalls = apiCalls + 1 return shield end
}
run(section(read("ElvUI/Core/Modules/Nameplates/Elements/HealthBar.lua"), "local function HidePlateLabel(text)", "function NP:Configure_PlateLabel("), env)
local bar = { shown = true, width = 200 }
function bar:IsShown() return self.shown end
function bar:GetWidth() return self.width end
function bar:CreateTexture() return widget() end
function bar:CreateFontString() return widget() end
local frame = { UnitType = "ENEMY_PLAYER", Health = bar, unit = "nameplate1" }
np:Configure_Absorb(frame)
np:Update_Absorb(frame)
assert(bar.Absorb.shown and not bar.AbsorbText.shown)
assert(bar.Absorb.width == 44)

health.absorb.showText = true
health.absorb.font, health.absorb.fontSize, health.absorb.fontOutline = "Expressway", 18, "MONOCHROMEOUTLINE"
np:Configure_Absorb(frame)
np:Update_Absorb(frame)
assert(bar.AbsorbText.shown and bar.AbsorbText.value == "+22000")
assert(bar.AbsorbText.font[1] == "Expressway" and bar.AbsorbText.font[2] == 18)
assert(bar.AbsorbText.font[3] == "MONOCHROMEOUTLINE")
assert(health.text.font ~= "Expressway" and health.text.fontSize ~= 18)
health.absorb.showText = false
np:Update_Absorb(frame)
assert(bar.Absorb.shown and not bar.AbsorbText.shown)
assert(bar.AbsorbText.value == "" and bar.AbsorbText.lastValue == nil)

health.absorb.enable = false
np:Configure_Absorb(frame)
local callsBefore = apiCalls
np:Update_Absorb(frame)
assert(not bar.Absorb.shown and not bar.AbsorbText.shown and apiCalls == callsBefore)
local fresh = { UnitType = frame.UnitType, Health = bar, unit = frame.unit }
bar.Absorb, bar.AbsorbText = nil, nil
np:Configure_Absorb(fresh)
np:Update_Absorb(fresh)
assert(not bar.Absorb and not bar.AbsorbText)
health.absorb = { enable = true, showText = true }
np:Configure_Absorb(frame)
assert(bar.AbsorbText.font[1] == health.text.font and bar.AbsorbText.font[2] == health.text.fontSize)
np:Update_Absorb(frame)
assert(bar.AbsorbText.shown)
shield = 0
np:Update_Absorb(frame)
assert(not bar.Absorb.shown and not bar.AbsorbText.shown)
shield, maximum = 22000, 0
np:Update_Absorb(frame)
assert(not bar.Absorb.shown and not bar.AbsorbText.shown)
maximum, shield = 10000, 22000
np:Update_Absorb(frame)
assert(bar.Absorb.width == 200)
env.UnitGetTotalAbsorbs = nil
np:Update_Absorb(frame)
assert(not bar.Absorb.shown and not bar.AbsorbText.shown)

local group, updates = { args = { healthGroup = { args = {} } } }, 0
function np:ConfigureAll() updates = updates + 1 end
run(section(read("ElvUI_Options/Core/Nameplates.lua"), "\tgroup.args.healthGroup.args.absorb = {", '\tif unit == "ENEMY_NPC" then\n\t\tgroup.args.threatText'), {
	group = group, unit = "ENEMY_PLAYER", NP = np,
	E = { db = { nameplates = np.db } },
	L = setmetatable({}, { __index = function(_, key) return key end }),
	AceGUIWidgetLSMlists = { font = {} }, C = { Values = { FontFlags = {}, FontSorting = {} } }
})
local options = group.args.healthGroup.args.absorb
health.absorb.enable, health.absorb.showText = false, false
assert(options.args.showText.disabled() and options.args.fontGroup.disabled())
options.set({ "enable" }, true)
assert(not options.args.showText.disabled() and options.args.fontGroup.disabled())
options.set({ "showText" }, true)
assert(not options.args.fontGroup.disabled())
for key, value in pairs({ font = "Expressway", fontSize = 20, fontOutline = "" }) do
	assert(options.args.fontGroup.args[key])
	options.set({ "fontGroup", key }, value)
	assert(options.get({ "fontGroup", key }) == value)
end
assert(updates == 5)
print("PASS: absorption defaults, visibility, independent fonts, legacy profiles and option callbacks")
