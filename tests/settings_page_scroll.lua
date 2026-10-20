-- Run from repository root: lua tests/settings_page_scroll.lua (Lua 5.1).
-- Exercises the actual FeedGroup with model widgets; does not emulate WoW UI.
local path = 'ElvUI_Options/Libraries/Ace3/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua'
local file = assert(io.open(path, 'r'))
local source = file:read('*a'); file:close()
assert(loadstring(source, '@' .. path))
local first = assert(source:find('function AceConfigDialog:FeedGroup(', 1, true))
local last = assert(source:find('\nlocal old_CloseSpecialWindows', first, true))
local feed = source:sub(first, last - 1)
local setup = [====[

AceConfigDialog={statuses={}}
function AceConfigDialog:GetStatusTable(app,path)
 local k=app..table.concat(path,'/')
 self.statuses[k]=self.statuses[k] or {}
 return self.statuses[k]
end
function pickfirstset(...) for i=1,select('#',...) do local v=select(i,...); if v~=nil then return v end end end
function GetSubOption(g,k) return g.args[k] end
function CheckOptionHidden(v) return v.hidden end
function GetOptionsMemberValue(k,g) return g[k] end
function GroupExists() return false end
function TreeOnButtonEnter() end
function TreeOnButtonLeave() end
local W={}
local pads={Frame=57,TreeGroup=20,TabGroup=53,DropdownGroup=28}
function W:GetUserData(k) return self.userdata[k] end
function W:SetUserData(k,v) self.userdata[k]=v end
function W:SetLayout(v) self.layout=v end
function W:SetCallback(k,v) self.callbacks[k]=v end
function W:SetStatusTable(t) self.status=t end
function W:SetTitle() end
function W:SetTabs(t) self.tabs=t end
function W:SetTree(t) self.tabs=t end
function W:SetGroupList(t) self.tabs=t end
function W:EnableButtonTooltips() end
function W:SetHeight(h) self.frame.h=h end
function W:ReleaseChildren() self.children={} end
function W:AddChild(c) c.parent=self; table.insert(self.children,c); self:DoLayout() end
function W:PerformLayout() self:DoLayout() end
function W:DoLayout()
 if self.busy then return end
 self.busy=true;self.layouts=self.layouts+1
 local avail=self.frame.h-(pads[self.type] or 0)
 self.content.h=avail
 local used=0
 for _,c in ipairs(self.children) do
  if self.layout=='fill' then c:SetHeight(avail)
  elseif c.height=='fill' then c:SetHeight(avail-used) end
  c:DoLayout();used=used+c.frame.h+3
 end
 if self.type=='ScrollFrame' then
  self.content.h=used; self.scrollBarShown=used>self.frame.h
 elseif self.type~='Frame' and self.layout~='fill' then
  self.frame.h=used+(pads[self.type] or 0);self.content.h=used
 end
 self.busy=nil
end
function W:SelectTab(v) self:Select(v) end
function W:SelectByValue(v) self:Select(v) end
function W:SetGroup(v) self:Select(v) end
function W:Select(v) if self.callbacks.OnGroupSelected then self.callbacks.OnGroupSelected(self,'OnGroupSelected',v) end end
gui={all={}}
function gui:Create(t)
 local w=setmetatable({type=t,children={},userdata={},callbacks={},layouts=0,frame={h=100},content={h=100}}, {__index=W})
 w.frame.GetHeight=function(f) return f.h end
 w.content.GetHeight=function(f) return f.h end
 table.insert(self.all,w);return w
end
function InjectInfo(w,options,group,path,root,app)
 local p={};for i,k in ipairs(path) do p[i]=k end
 w.info={options=options,path=p,root=root,app=app}
end
function GroupSelected(w,event,v)
 local u=w.info;local p={};for i,k in ipairs(u.path) do p[i]=k end
 p[#p+1]=v;w:ReleaseChildren()
 AceConfigDialog:FeedGroup(u.app,u.options,w,u.root,p)
end
function BuildGroups(g)
 local t={};for k,v in pairs(g.args) do if v.type=='group' and not v.inline and not v.hidden then t[#t+1]={value=k,order=v.order or 1} end end
 table.sort(t,function(a,b)return a.order<b.order end);return t
end
function BuildSelect(g)
 local t=BuildGroups(g);local o={};local l={};for _,v in ipairs(t)do o[#o+1]=v.value;l[v.value]=v.value end;return l,o
end
function FeedOptions(app,options,w,root,path,g)
 if g.testHeight then
  local c=gui:Create('TestBlock');c.frame.h=g.testHeight
  c.DoLayout=function()end
  w:AddChild(c)
 end
end
function fixture(app,kind)
 local nested={type='group',name='Nested',testHeight=173,args={}}
 local buffs={type='group',name='Buffs',order=1,testHeight=844,args={nested=nested}}
 local debuffs={type='group',name='Debuffs',order=2,testHeight=100,args={nested=nested}}
 local auras={type='group',name='Auras',childGroups=kind,testHeight=272,args={buffs=buffs,debuffs=debuffs}}
 local opts={type='group',childGroups='ElvUI_HiddenTree',args={auras=auras}}
 local win=gui:Create('Frame');win.frame.h=600
 local root=gui:Create('TreeGroup');root.frame.h=543
 AceConfigDialog:FeedGroup(app,opts,root,win,{'auras'})
 return root,opts,win
end
function count(t) local n=0;for _,w in ipairs(gui.all) do if w.type==t then n=n+1 end end;return n end
]====]
local checks = [====[

assert(root.layout == 'fill')
local scroll = root.children[1]
assert(scroll.type == 'ScrollFrame' and count('ScrollFrame') == 1)
assert(scroll.frame.h > 0 and scroll.content.h > scroll.frame.h and scroll.scrollBarShown)
for _, w in ipairs(gui.all) do
 if w:GetUserData('ElvUIPageScroll') then
  assert(w:GetUserData('ElvUIPageScroll') == scroll and w.height ~= 'fill')
 end
end
local selector = scroll.children[2]
local height, layouts = scroll.content.h, scroll.layouts
selector:Select('debuffs')
assert(scroll.layouts > layouts and scroll.content.h < height)
selector:Select('buffs')
assert(scroll.content.h == height)
root.frame.h = 1000; root:DoLayout()
assert(scroll.frame.h == 980)
root.frame.h = 450; root:DoLayout()
assert(scroll.frame.h == 430 and scroll.scrollBarShown)
]====]
local function execute(env, text)
 local chunk = assert(loadstring(text))
 setfenv(chunk, env)
 return chunk()
end
local function environment()
 local env = setmetatable({}, { __index = _G })
 execute(env, setup)
 execute(env, feed)
 return env
end
for _, kind in ipairs({ 'tab', 'select', 'tree' }) do
 local env = environment()
 env.root = env.fixture('ElvUI', kind)
 execute(env, checks)
end
local legacy = environment()
legacy.root = legacy.fixture('OtherAddon', 'tab')
execute(legacy, [====[
 assert(root.layout == 'flow' and root.children[2].type == 'TabGroup')
 assert(root.children[2].height == 'fill')
 assert(not root.children[2]:GetUserData('ElvUIPageScroll'))
]====])
local navigation = environment()
execute(navigation, [====[
 local window = gui:Create('Frame'); window.frame.h = 600
 local options = { type='group', childGroups='ElvUI_HiddenTree', args={a={type='group',name='A',testHeight=20,args={}}} }
 AceConfigDialog:FeedGroup('ElvUI', options, window, window, {}, true)
 assert(window.children[1].type == 'TreeGroup' and window.children[1].height == 'fill')
]====])
print('PASS: one viewport; nested tab/select/tree; resize; tab changes; legacy app; fixed navigation; Lua 5.1 syntax')
