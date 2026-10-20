-- Run from the repository root: lua tests/treegroup_autoheight.lua (Lua 5.1).
-- Loads the real TreeGroup methods without constructing WoW frames.
local path = 'ElvUI_Options/Libraries/Ace3/AceGUI-3.0/widgets/AceGUIContainer-TreeGroup.lua'
local gui, constructor = {}, nil
function gui:GetWidgetVersion() return 0 end
function gui:RegisterWidgetType(_, value) constructor = value end
local uiParent = {}
local env = setmetatable({ LibStub = function() return gui end, UIParent = uiParent }, { __index = _G })
local chunk = assert(loadfile(path))
setfenv(chunk, env); chunk()
local methods
for index = 1, 30 do
	local name, value = debug.getupvalue(constructor, index)
	if not name then break end
	if name == 'methods' then methods = value; break end
end
assert(methods, 'TreeGroup constructor must expose its real methods')
local function widget()
	local result = { h = 60, testContentHeight = 40, buttons = {}, lines = {}, localstatus = { groups = {}, scrollvalue = 0 } }
	for name, method in pairs(methods) do result[name] = method end
	result.tree = {
		{value = 'a', text = 'A', children = {{value = 'a1', text = 'A1'}, {value = 'a2', text = 'A2'}}},
		{value = 'b', text = 'B'}, {value = 'c', text = 'C'}, {value = 'd', text = 'D'}
	}
	result.frame = {
		obj = result,
		GetParent = function() return uiParent end,
		GetHeight = function() return result.h end,
		SetScript = function(self, event, fn) self[event] = fn end
	}
	result.treeframe = {
		shown = true,
		IsShown = function(self) return self.shown end,
		GetHeight = function() return result.h - (result.navInset or 0) - 0.001 end -- skin inset + client rounding
	}
	function result:SetHeight(height)
		local changed = self.h ~= height
		self.h = height
		-- Mimic the size event which may reenter RefreshTree.
		if changed and self.testReentrant then self:RefreshTree() end
	end
	function result:DoLayout()
		self.layoutCalls = (self.layoutCalls or 0) + 1
		self:LayoutFinished(nil, self.testContentHeight)
	end
	return result
end
local tree = widget()
tree:BuildLevel(tree.tree, 1)
tree:LayoutFinished(nil, 40)
assert(tree.h >= #tree.lines * 18 + 20, 'natural height must fit the whole navigation, not just the selected content')
assert(math.floor((tree.treeframe:GetHeight() - 20) / 18) >= #tree.lines, 'all rows must fit despite fractional rounding')
-- Changing visible branches reflows all owners without recursive layout loops.
local page = { layoutCalls = 0 }
function page:DoLayout() self.layoutCalls = self.layoutCalls + 1 end
local parent = { parent = page, layoutCalls = 0 }
function parent:DoLayout() self.layoutCalls = self.layoutCalls + 1 end
tree.parent, tree.testReentrant = parent, true
tree:RefreshTree()
assert(tree.autoHeightLineCount == 4 and tree.layoutCalls == 1)
assert(parent.layoutCalls == 1 and page.layoutCalls == 1)
tree.localstatus.groups.a = true
tree:RefreshTree()
assert(#tree.lines == 6 and tree.h >= 6 * 18 + 20)
assert(parent.layoutCalls == 2 and page.layoutCalls == 2)
tree.localstatus.groups.a = false
tree:RefreshTree()
assert(#tree.lines == 4 and math.floor((tree.treeframe:GetHeight() - 20) / 18) >= 4)
assert(parent.layoutCalls == 3 and page.layoutCalls == 3)
local calls = tree.layoutCalls
tree:RefreshTree()
assert(tree.layoutCalls == calls, 'unchanged tree must not keep reflowing')
-- A taller settings panel must still determine natural height.
tree:LayoutFinished(nil, 500)
assert(tree.h == 520)
-- Fixed-height trees retain their real internal scrolling behaviour.
local fixed = widget(); fixed.height = 'fill'
fixed:BuildLevel(fixed.tree, 1); fixed:LayoutFinished(nil, 40)
assert(fixed.h == 60)
fixed:RefreshTree(); assert(not fixed.layoutCalls)
-- Hidden tree navigation must not force extra height.
local hidden = widget(); hidden.treeframe.shown = false
hidden:BuildLevel(hidden.tree, 1); hidden:LayoutFinished(nil, 40)
assert(hidden.h == 60)
local locked = widget(); locked.noAutoHeight = true
locked:BuildLevel(locked.tree, 1); locked:LayoutFinished(nil, 500)
assert(locked.h == 60)
locked:RefreshTree(); assert(not locked.layoutCalls)
-- The real ElvUI skin shifts treeframe TOPLEFT down by 2px. This used to
-- leave the viewport too short even after the line-count minimum was added.
for _, rows in ipairs({ 1, 4 }) do
	local skinned = widget()
	skinned.tree = {}
	for row = 1, rows do skinned.tree[row] = { value = tostring(row), text = tostring(row) } end
	skinned.navInset, skinned.testContentHeight = 2, 0
	skinned:BuildLevel(skinned.tree, 1)
	skinned:LayoutFinished(nil, 0)
	assert(math.floor((skinned.treeframe:GetHeight() - 20) / 18) >= rows, 'skin inset must not make navigation scroll again')
end
-- Run the real ElvUI skin wrapper too: it applies TOPLEFT(0, -2) after the
-- library RefreshTree call, so geometry can change with the same row count.
local skinFile = assert(io.open('ElvUI/Core/Modules/Skins/Addons/Ace3.lua', 'r'))
local skinSource = skinFile:read('*a'); skinFile:close()
local skinFirst = assert(skinSource:find('function S:Ace3_RefreshTree(', 1, true))
local skinLast = assert(skinSource:find('\nfunction S:Ace3_RegisterAsContainer', skinFirst, true))
local skinEnv = setmetatable({ S = {}, E = { private = { skins = { ace3Enable = false } } } }, { __index = _G })
local skinChunk = assert(loadstring(skinSource:sub(skinFirst, skinLast - 1)))
setfenv(skinChunk, skinEnv); skinChunk()
for _, rows in ipairs({ 1, 4 }) do
	local skinned = widget()
	skinned.tree = {}
	for row = 1, rows do skinned.tree[row] = {value = tostring(row), text = tostring(row)} end
	skinned.testContentHeight, skinned.testReentrant = 0, true
	skinned.border = { ClearAllPoints = function() end, Point = function() end }
	skinned.treeframe.Point = function(_, point, _, y)
		assert(point == 'TOPLEFT')
		local inset = -y
		if skinned.navInset ~= inset then skinned.navInset = inset; skinned:RefreshTree() end
	end
	skinned.old_RefreshTree = skinned.RefreshTree
	skinned.RefreshTree = skinEnv.S.Ace3_RefreshTree
	skinned:RefreshTree()
	for _ = 1, 3 do
		if skinned.frame.OnUpdate then skinned.frame.OnUpdate(skinned.frame) else skinned:RefreshTree() end
	end
	assert(skinned.navInset == 2)
	assert(math.floor((skinned.treeframe:GetHeight() - 20) / 18) >= rows, 'real skin wrapper must leave all navigation rows visible')
end
-- Skin geometry can change after RefreshTree has already seen this line count.
local changed = widget(); changed.testReentrant, changed.testContentHeight = true, 0
changed:RefreshTree()
local before = changed.layoutCalls
changed.navInset = 6
changed:RefreshTree()
assert(changed.layoutCalls == before + 1, 'same row count must relayout when the viewport becomes too short')
assert(math.floor((changed.treeframe:GetHeight() - 20) / 18) >= #changed.lines)
assert(not changed.autoHeightUpdating)
tree:OnRelease(); assert(tree.autoHeightLineCount == nil and tree.autoHeightUpdating == nil)
print('PASS: navigation height; real ElvUI skin (1/4 rows); late viewport changes; rounding; expand/collapse; reentry; fixed/hidden/locked; pool reset')
