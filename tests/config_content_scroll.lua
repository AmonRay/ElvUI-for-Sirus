-- Run from repository root: lua tests/config_content_scroll.lua (Lua 5.1).
-- Executes the actual ElvUI scroll code with a small native-frame geometry stub.
-- This reproduces inverted nested rectangles, not the WoW rendering/input stack.
local file = assert(io.open('ElvUI/Core/General/Config.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('-- The outer viewport belongs to ElvUI', 1, true))
local last = assert(source:find('\nfunction E:Config_SetStatusText', first, true))
local fragment = source:sub(first, last - 1)
local Frame = {}
Frame.__index = Frame
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetTop()
	if self.topFn then return self.topFn() end
	if self.all then return self.all:GetTop() end
	for _, p in ipairs(self.points) do
		if p[1] == 'TOPLEFT' then
			local relative = p[2] or self.parent
			local top = relative:GetTop()
			if relative.scrollChild == self then top = top + (relative.offset or 0) end
			return top + (p[5] or 0)
		end
	end
	return self.top or 600
end
function Frame:GetBottom()
	if self.bottomFn then return self.bottomFn() end
	if self.all then return self.all:GetBottom() end
	for _, p in ipairs(self.points) do
		if p[1] == 'BOTTOMRIGHT' then return (p[2] or self.parent):GetBottom() + (p[5] or 0) end
	end
	return self:GetTop() - self.h
end
function Frame:GetHeight() return self:GetTop() - self:GetBottom() end
function Frame:GetWidth()
	if self.all then return self.all:GetWidth() end
	local left, right
	for _, p in ipairs(self.points) do
		if p[1] == 'TOPLEFT' then left = p[4] or 0 end
		if p[1] == 'BOTTOMRIGHT' then right = p[4] or 0 end
	end
	if left and right then return self.parent:GetWidth() + right - left end
	return self.w
end
function Frame:ClearAllPoints() self.points = {}; self.all = nil end
function Frame:SetAllPoints(other) self.all = other end
function Frame:Point(...) self:SetPoint(...) end
function Frame:SetPoint(point, relative, relativePoint, x, y)
	if type(relative) == 'number' then x, y, relative = relative, relativePoint, self.parent end
	if not relative then relative = self.parent end
	for i, p in ipairs(self.points) do if p[1] == point then self.points[i] = {point, relative, relativePoint, x, y}; return end end
	self.points[#self.points + 1] = {point, relative, relativePoint, x, y}
end
function Frame:Fire(event, ...)
	if self.scripts[event] then self.scripts[event](self, ...) end
	for _, fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end
end
function Frame:SetSize(w, h)
	local changed = self.w ~= w or self.h ~= h
	self.w, self.h = w, h
	if changed then self:Fire('OnSizeChanged', w, h) end
end
function Frame:SetWidth(w) self.w = w end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:HookScript(event, fn)
	self.hooks[event] = self.hooks[event] or {}
	table.insert(self.hooks[event], fn)
end
function Frame:IsShown() return self.shown end
function Frame:Show() if not self.shown then self.shown = true; self:Fire('OnShow') end end
function Frame:Hide() if self.shown then self.shown = false; self:Fire('OnHide') end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:SetVerticalScroll(v) self.offset = v end
function Frame:EnableMouseWheel(v) self.mouseWheel = v end
function Frame:SetOrientation() end
function Frame:SetValueStep() end
function Frame:SetVertexColor() end
function Frame:SetThumbTexture() self.thumb = setmetatable({w = 8, h = 24, points = {}, scripts = {}, hooks = {}, shown = true}, Frame) end
function Frame:GetThumbTexture() return self.thumb end
function Frame:GetMinMaxValues() return self.low or 0, self.high or 0 end
function Frame:SetMinMaxValues(low, high) self.low, self.high = low, high; self:SetValue(self:GetValue()) end
function Frame:GetValue() return self.value or 0 end
function Frame:SetValue(value)
	value = math.max(self.low or 0, math.min(self.high or 0, value))
	if self.value ~= value then self.value = value; self:Fire('OnValueChanged', value) end
end
local function create(kind, _, parent)
	return setmetatable({kind = kind, parent = parent, w = 800, h = 600, points = {}, scripts = {}, hooks = {}, shown = true}, Frame)
end
local engine = { media = { blankTex = 'blank' }, layouts = 0 }
local skins = { calls = 0 }
function skins:HandleSirusScrollBar() self.calls = self.calls + 1 end
local factory = assert(loadstring('return function(E, S, CreateFrame)\nlocal min = math.min\n' .. fragment .. '\nreturn Config_ContentHeight, Config_UpdateContentScroll, Config_CreateContentScroll\nend'))()
local measure, update, createScroll = factory(engine, skins, create)
local window = create('Frame'); window.top = 600
window.bottomHolder = create('Frame'); window.bottomHolder.h = 37
window.obj = {children = {}, content = create('Frame', nil, window)}
function window.obj:DoLayout() engine.layouts = engine.layouts + 1 end
function engine:Config_GetWindow() return self.window end
function engine:Config_GetStatus() return {}, self.selected end
engine.window, engine.selected = window, 'auras'
local clip = createScroll(window, false)
window.obj.content:SetParent(clip.child)
engine:Config_ContentPlacement(window, window.obj.content, false, false)
local function rectangle(topFn, bottomFn, parent)
	local frame = create('Frame', nil, parent)
	frame.topFn, frame.bottomFn = topFn, bottomFn
	return frame
end
local function rootTop() return window.obj.content:GetTop() end
local function rootBottom() return rootTop() - clip.child:GetHeight() end
local function makeContainer(kind, topFn, bottomFn, insetTop, insetBottom, parent)
	local frame = rectangle(topFn, bottomFn, parent)
	return {type = kind, frame = frame, children = {}, content = rectangle(function() return frame:GetTop() - insetTop end, function() return frame:GetBottom() + insetBottom end, frame)}
end
local root = makeContainer('TreeGroup', rootTop, rootBottom, 10, 10, window.obj.content)
local tab = makeContainer('TabGroup', function() return rootTop() - 272 end, rootBottom, 43, 10, root.content)
local nested = makeContainer('TreeGroup', function() return tab.content:GetTop() - 858 end, function() return tab.content:GetBottom() end, 10, 10, tab.content)
local innerFrame = rectangle(function() return nested.content:GetTop() end, function() return nested.content:GetBottom() end, nested.content)
local innerContent = rectangle(function() return innerFrame:GetTop() end, function() return innerFrame:GetTop() - 173 end, innerFrame)
local inner = {type = 'ScrollFrame', frame = innerFrame, scrollframe = innerFrame, content = innerContent, children = {}}
innerFrame.obj = inner
root.children = {tab}; tab.children = {nested}; nested.children = {inner}; window.obj.children = {root}
clip.child:SetSize(clip:GetWidth(), 873)
assert(math.abs(nested.frame:GetHeight() + 310) < 0.01)
assert(math.abs(innerFrame:GetHeight() + 330) < 0.01)
assert(math.abs(measure(root) - 1386) < 0.01)
local function settle()
	for _ = 1, 12 do update(clip); if not clip.dirty then return end end
	error('content geometry failed to settle')
end
clip.dirty = true; settle()
assert(clip:GetHeight() > 0 and innerFrame:GetHeight() >= 173, 'nested viewport must no longer be inverted')
assert(clip.scrollbar:IsShown() and select(2, clip.scrollbar:GetMinMaxValues()) > 0)
assert(skins.calls == 1)
local layouts = engine.layouts; update(clip); assert(engine.layouts == layouts, 'idle must not relayout')
-- Emulate AceGUI Frame.OnHeightSet overwriting the cache on a window resize.
window.obj.content.height = 543
clip.dirty = true; settle()
assert(window.obj.content.height == clip.child:GetHeight())
assert(engine.layouts > layouts, 'stale Frame height cache must be corrected')
clip:Fire('OnMouseWheel', -1)
assert(clip.scrollbar:GetValue() == 36 and clip.offset == 36)
local natural = measure(root)
innerFrame:Fire('OnMouseWheel', -1)
assert(clip.scrollbar:GetValue() == 72, 'non-scrollable inner frame must forward the wheel')
assert(measure(root) == natural, 'outer scroll offset must not affect natural height')
-- An independently scrollable inner control must keep ownership of the wheel.
local savedBottom = innerContent.bottomFn
innerContent.bottomFn = function() return innerFrame:GetTop() - 2000 end
innerFrame:Fire('OnMouseWheel', -1)
assert(clip.scrollbar:GetValue() == 72)
innerContent.bottomFn = savedBottom
-- Short pages must release height and reset a stale scroll offset.
local short = rectangle(rootTop, function() return rootTop() - 40 end, window.obj.content)
window.obj.children = {{type = 'Label', frame = short}}
engine.selected = 'short'; clip.dirty = true; settle()
assert(not clip.scrollbar:IsShown() and clip.offset == 0)
assert(clip.child:GetHeight() == math.ceil(clip:GetHeight()))
-- Revisit long content, resize, and account for visible status text.
window.obj.children = {root}; engine.selected = 'auras'; clip.dirty = true; settle()
window:SetSize(1000, 800); clip.dirty = true; settle()
assert(clip.child:GetWidth() == clip:GetWidth())
engine:Config_ContentPlacement(window, window.obj.content, false, true); settle()
assert(clip:GetBottom() - window:GetBottom() == 25)
-- Closing/reusing a shared AceGUI Frame must leave hidden wrappers inert.
clip:Hide(); local offset = clip.offset; innerFrame:Fire('OnMouseWheel', -1); assert(clip.offset == offset)
engine.window = nil; clip.dirty = true; update(clip); assert(clip.offset == offset)
-- Exercise the actual close handler: restore parentage before AceGUI pooling.
local closeFirst = assert(source:find('function E:Config_WindowClosed()', 1, true))
local closeChunk = source:sub(closeFirst, first - 1)
assert(loadstring('return function(E) local ConfigLogoTop = true; ' .. closeChunk .. '\nend'))()(engine)
window.leftHolder, window.topHolder = create('Frame'), create('Frame')
window.leftHolder.slider = create('Slider')
window.leftHolder.LogoTop, window.leftHolder.LogoBottom = {}, {}
window.topHolder.version = create('Frame')
window.closeButton, window.originalClose = create('Button'), create('Button')
window.obj.titlebg = create('Frame')
engine.private = { skins = { ace3Enable = true } }
function engine:StopElasticize() end
function engine:Config_RestoreOldPosition(region)
	if region == window.obj.content then assert(region:GetParent() == window) end
end
clip:Show(); clip.scrollbar:Show()
engine.Config_WindowClosed(window)
assert(not clip:IsShown() and not clip.scrollbar:IsShown())
assert(window.obj.content:GetParent() == window)
-- Skin-off creation uses the same native scroll mechanism.
local plain = create('Frame')
createScroll(plain, true)
assert(skins.calls == 1)
print('PASS: -310/-330 geometry; bar/wheel; nested forwarding; shrink; resize; idle; close/pooling; skin-off')
