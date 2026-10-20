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
		GetParent = function() return uiParent end,
		SetScript = function(self, event, fn) self[event] = fn end
	}
	result.treeframe = {
		shown = true,
		IsShown = function(self) return self.shown end,
		GetHeight = function() return result.h - 0.001 end -- client rounding
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
assert(#tree.lines == 4 and tree.h == 4 * 18 + 21)
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
tree:OnRelease(); assert(tree.autoHeightLineCount == nil)
print('PASS: natural tree fits navigation; rounding; expand/collapse; ancestors; reentry; fixed/hidden/locked trees; pool reset')
