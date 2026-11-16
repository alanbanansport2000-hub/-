-- DeepWoods Hub v2.2 STATIONARY | Survive Deep in the Woods
-- STANDING FARM: NEVER calls MoveTo, never changes CameraType/Camera CFrame.
-- Swings only toward visible candidate trees; distant server hits are NOT guaranteed.
-- Self-contained Roblox Luau script. No network imports or key system.
-- Farm uses confirmed GUI Swing signal; never emulates screen taps.
-- Classification of killer is a heuristic (MaxHealth > 100), not official role data.
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')
local CollectionService = game:GetService('CollectionService')
local CAS = game:GetService('ContextActionService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')
local env = (getgenv and getgenv()) or _G

for _, key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload',
 'DeepWoodsHub15_Unload','DeepWoodsHub16_Unload','DeepWoodsHub17_Unload',
 'DeepWoodsHub18_Unload','DeepWoodsHub19_Unload','DeepWoodsHub20_Unload','DeepWoodsHub21_Unload','DeepWoodsHub211_Unload','DeepWoodsHub22_Unload'}) do
 if type(env[key])=='function' then pcall(env[key]) end
end
-- Remove only our own old UI left by an interrupted run.
for _,name in ipairs({'DeepWoodsHub_OwnWindow','DeepWoodsHub_OnlyOwnGui',
 'DeepWoodsHub_v12','DeepWoodsHub_v13_FIX','DeepWoodsHub_v14_STABLE',
 'DeepWoodsHub_v15_FIX','DeepWoodsHub_v16_FIX','DeepWoodsHub_v17_WOOD',
 'DeepWoodsHub_v18_TARGET','DeepWoodsHub_v19_COMPACT','DeepWoodsHub_v20_ANTIGHOST','DeepWoodsHub_v21_FAST','DeepWoodsHub_v211_TAPFIX','DeepWoodsHub_v22_STATIONARY'}) do
 local old=PG:FindFirstChild(name)
 if old and old:IsA('ScreenGui') then pcall(function() old:Destroy() end) end
end
for _,name in ipairs({'DeepWoodsHub_Effects','DeepWoodsHub_LocalVisuals',
 'DeepWoodsHub_PlayerEffects','DeepWoodsHub_v13_Visuals',
 'DeepWoodsHub_v14_Effects','DeepWoodsHub_v15_Effects','DeepWoodsHub_v16_Effects',
 'DeepWoodsHub_v17_Effects','DeepWoodsHub_v18_Effects','DeepWoodsHub_v19_Effects','DeepWoodsHub_v20_Effects','DeepWoodsHub_v21_Effects','DeepWoodsHub_v211_Effects','DeepWoodsHub_v22_Effects'}) do
 local old=workspace:FindFirstChild(name)
 if old and old:IsA('Folder') then pcall(function() old:Destroy() end) end
end

local active=true
local connections={}
local role=nil -- 'farmer' or 'killer'
local cfg={esp=false,speed=false,noclip=false,wood=false}
local walkSpeed=32
local walkChoices={24,32,40,60,90}
local speedHum,oldSpeed=nil,nil
local oldCollisions={}
local woodTarget=nil
local woodStarted=0
local woodAttackStarted=0
local woodHits=0
local woodNext=0
local woodCooldown=setmetatable({}, {__mode='k'})
-- A harvested tree can leave an old model at the same coordinates.
-- Blacklist both the old Instance and its position temporarily.
local emptySpots = {}
local zoneCenter = nil
local ZONE_RADIUS = 10 -- studs around current player, NO movement
local MAX_STATIONARY_RANGE = 10 -- target search/attempt range, server may reject distant hits
local MAX_SWINGS_UNVERIFIED = 6
local MAX_ATTACK_TIME = 3.7
local woodLastFingerprint=nil
local woodLastHealth=nil
local woodLastApproachPos=nil
local woodLastApproachAt=0
local woodSwingsWithoutEffect=0
-- Speed defaults to ON, but can be disabled if this game's server rejects it.
local fastFarm=true
local FAST_SWING_INTERVAL=.43 -- no speculative direct server remotes/bursts
local SAFE_SWING_INTERVAL=.56 -- known to work in the prior version
local farmHumanoid=nil
local woodValueAtTarget=nil
local treeList={}
local treeScanAt=-99
local swingButton=nil
local swingScanAt=-99
local marker=nil
local espData={}
local farmStatus='Стационарная рубка выключена'
local C={
 bg=Color3.fromRGB(14,20,31),panel=Color3.fromRGB(25,34,50),
 item=Color3.fromRGB(38,50,70),edge=Color3.fromRGB(57,92,121),
 blue=Color3.fromRGB(75,187,235),text=Color3.fromRGB(238,245,251),
 muted=Color3.fromRGB(170,187,207),green=Color3.fromRGB(46,193,139),
 red=Color3.fromRGB(255,92,99),off=Color3.fromRGB(75,87,104)
}
local function conn(sig,fn)
 local c=sig:Connect(fn)
 connections[#connections+1]=c
 return c
end
local function ui(class,parent,props)
 local obj=Instance.new(class)
 for k,v in pairs(props or {}) do
  assert(type(k)=='string','Bad UI property: '..tostring(k))
  obj[k]=v
 end
 obj.Parent=parent
 return obj
end
local function radius(obj,r) ui('UICorner',obj,{CornerRadius=UDim.new(0,r or 9)}) end
local function outline(obj,col,w) ui('UIStroke',obj,{Color=col or C.edge,Thickness=w or 1,Transparency=.2}) end
local function tween(obj,props,duration)
 local ok=pcall(function()
  TweenService:Create(obj,TweenInfo.new(duration or .16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props):Play()
 end)
 if not ok then for k,v in pairs(props) do pcall(function()obj[k]=v end) end end
end
local function char()
 local c=LP.Character
 return c,c and c:FindFirstChildOfClass('Humanoid'),c and c:FindFirstChild('HumanoidRootPart')
end
local function viewport()
 local cam=workspace.CurrentCamera
 return cam and cam.ViewportSize or Vector2.new(770,400)
end
local function restoreSpeed()
 if speedHum and speedHum.Parent and oldSpeed~=nil then
  pcall(function() speedHum.WalkSpeed=oldSpeed end)
 end
 speedHum,oldSpeed=nil,nil
end
local function restoreCollision()
 for p,v in pairs(oldCollisions) do
  if p and p.Parent then pcall(function() p.CanCollide=v end) end
 end
 table.clear(oldCollisions)
end
local function stopAim()
 -- Never set CameraType=Scriptable: it freezes camera control on Android.
 if marker then marker.Adornee=nil end
end
local function stopWood()
 cfg.wood=false
 woodTarget=nil
 woodHits=0
 woodLastFingerprint=nil
 woodLastHealth=nil
 woodSwingsWithoutEffect=0
 woodValueAtTarget=nil
 farmHumanoid=nil
 zoneCenter=nil
 stopAim()
end
local function clearEsp(p)
 local d=espData[p]
 if d then
  for _,v in ipairs(d.items) do pcall(function()v:Destroy()end) end
  espData[p]=nil
 end
end
local screen=ui('ScreenGui',PG,{Name='DeepWoodsHub_v22_STATIONARY',ResetOnSpawn=false,
 IgnoreGuiInset=true,DisplayOrder=950,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local effects=ui('Folder',workspace,{Name='DeepWoodsHub_v22_Effects'})
local vw=viewport()
local PW=math.min(290,math.max(245,vw.X-22))
local PH=math.min(252,math.max(215,vw.Y-24))
local win=ui('Frame',screen,{Name='Window',Active=true,BorderSizePixel=0,
 BackgroundColor3=C.bg,Size=UDim2.fromOffset(PW,PH),
 Position=UDim2.fromOffset(math.max(10,math.floor((vw.X-PW)/2)),math.max(12,math.floor((vw.Y-PH)/2)))})
radius(win,13);outline(win,C.blue,1.25)
local top=ui('Frame',win,{Name='Header',Active=true,BorderSizePixel=0,
 Size=UDim2.new(1,0,0,36),BackgroundColor3=C.panel})
radius(top,12)
local dragHandle=ui('TextButton',top,{Text='🌲  DeepWoods  2.2',Font=Enum.Font.GothamBold,
 TextColor3=C.text,TextXAlignment=Enum.TextXAlignment.Left,TextSize=12,
 BackgroundTransparency=1,AutoButtonColor=false,Active=true,
 Position=UDim2.fromOffset(9,0),Size=UDim2.new(1,-130,1,0),ZIndex=3})
local roleChip=ui('TextButton',top,{Text='РОЛЬ',Font=Enum.Font.GothamBold,
 TextColor3=C.muted,TextSize=9,BackgroundColor3=C.item,BorderSizePixel=0,
 Position=UDim2.new(1,-120,0,7),Size=UDim2.fromOffset(71,23),ZIndex=4})
radius(roleChip,7)
local mini=ui('TextButton',top,{Text='−',Font=Enum.Font.GothamBold,
 TextSize=19,TextColor3=C.text,BackgroundColor3=C.item,BorderSizePixel=0,
 Position=UDim2.new(1,-38,0,5),Size=UDim2.fromOffset(30,27),ZIndex=4})
radius(mini,7)
local bubble=ui('TextButton',screen,{Name='FloatingIcon',Text='🌲',Font=Enum.Font.GothamBold,
 TextColor3=C.text,TextSize=23,BackgroundColor3=C.bg,BorderSizePixel=0,
 Size=UDim2.fromOffset(46,46),Position=UDim2.fromOffset(18,math.floor(vw.Y/2)),
 Visible=false,Active=true,AutoButtonColor=true,ZIndex=20})
radius(bubble,14);outline(bubble,C.blue,1.6)
local footer=ui('TextLabel',win,{Text='Выбери роль',Font=Enum.Font.Gotham,
 TextSize=10,TextColor3=C.muted,BackgroundColor3=C.panel,BorderSizePixel=0,
 Position=UDim2.new(0,7,1,-30),Size=UDim2.new(1,-14,0,25),
 TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center})
radius(footer,7)
local function status(msg)
 if active and footer.Parent then footer.Text=tostring(msg) end
end
local function click(button,fn)
 local last=-9
 local function call()
  if not active or os.clock()-last<.38 then return end
  last=os.clock()
  local ok,err=pcall(fn)
  if not ok then status('Ошибка: '..tostring(err):sub(1,65)) end
 end
 -- Activated is already a cross-platform click event (touch, mouse, gamepad).
 -- Connecting MouseButton1Click as well double-toggles switches on Android.
 conn(button.Activated,call)
end
local bubbleBlock=0
local bubbleMoved=false
local function draggable(handle,target,isBubble)
 local startInput,startP,fromP=nil,nil,nil
 local didMove=false
 local function onMove(input)
  if not startInput or not startP then return end
  if startInput.UserInputType==Enum.UserInputType.Touch then
   if input~=startInput then return end
  elseif input.UserInputType~=Enum.UserInputType.MouseMovement and input~=startInput then return end
  local delta=input.Position-startP
  if delta.Magnitude>=5 then didMove=true end
  if not didMove then return end
  local v=viewport()
  local x=math.clamp(fromP.X.Offset+delta.X,12,math.max(12,v.X-target.AbsoluteSize.X-12))
  local y=math.clamp(fromP.Y.Offset+delta.Y,15,math.max(15,v.Y-target.AbsoluteSize.Y-15))
  target.Position=UDim2.fromOffset(x,y)
  if isBubble then bubbleBlock=os.clock()+.38; bubbleMoved=true end
 end
 conn(handle.InputBegan,function(input)
  if startInput then return end
  if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
   startInput=input;startP=input.Position;fromP=target.Position;didMove=false
  end
 end)
 conn(handle.InputChanged,onMove)
 conn(UIS.InputChanged,onMove)
 local function finish(input)
  if startInput and (input==startInput or (startInput.UserInputType==Enum.UserInputType.MouseButton1
    and input.UserInputType==Enum.UserInputType.MouseButton1)) then
   if didMove and isBubble then bubbleBlock=os.clock()+.4 end
   startInput=nil;startP=nil;fromP=nil
  end
 end
 conn(handle.InputEnded,finish)
 conn(UIS.InputEnded,finish)
end
draggable(dragHandle,win,false)
draggable(bubble,bubble,true)
local function shrink()
 local v=viewport()
 if not bubbleMoved then bubble.Position=UDim2.fromOffset(15,math.floor((v.Y-46)/2)) end
 local x=math.clamp(bubble.Position.X.Offset,12,math.max(12,v.X-58))
 local y=math.clamp(bubble.Position.Y.Offset,16,math.max(16,v.Y-62))
 bubble.Position=UDim2.fromOffset(x,y)
 win.Visible=false
 bubble.Size=UDim2.fromOffset(40,40)
 bubble.Visible=true
 tween(bubble,{Size=UDim2.fromOffset(46,46)},.17)
end
local function expand()
 local v=viewport()
 local x=math.clamp(bubble.AbsolutePosition.X,10,math.max(10,v.X-PW-10))
 local y=math.clamp(bubble.AbsolutePosition.Y,10,math.max(10,v.Y-PH-10))
 bubble.Visible=false
 win.Position=UDim2.fromOffset(x,y+7)
 win.Visible=true
 tween(win,{Position=UDim2.fromOffset(x,y)},.16)
end
click(mini,shrink)
click(bubble,function() if os.clock()>=bubbleBlock then expand() end end)

-- All roles share just one small window. Pages are constructed once.
local rolePage=ui('Frame',win,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,41),Size=UDim2.new(1,-16,1,-77),Visible=true})
local gamePage=ui('Frame',win,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,41),Size=UDim2.new(1,-16,1,-77),Visible=false})
local killerPage=ui('Frame',win,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,41),Size=UDim2.new(1,-16,1,-77),Visible=false})
local function caption(parent,txt,y,h,size)
 return ui('TextLabel',parent,{Text=txt,Font=Enum.Font.Gotham,
 TextSize=size or 11,TextWrapped=true,TextColor3=C.muted,
 TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,
 Position=UDim2.new(0,0,0,y),Size=UDim2.new(1,0,0,h)})
end
caption(rolePage,'Выбери сторону',5,25,15).Font=Enum.Font.GothamBold
caption(rolePage,'Меню покажет только функции выбранной роли',29,27,10)
local function roleButton(title,x,width)
 local b=ui('TextButton',rolePage,{Text=title,Font=Enum.Font.GothamBold,
 TextSize=13,TextColor3=C.text,BackgroundColor3=C.item,
 BorderSizePixel=0,Position=UDim2.new(0,x,.57,0),Size=UDim2.new(0,width,0,59),Active=true})
 radius(b,10);outline(b,C.edge,1)
 local scale=ui('UIScale',b,{Scale=1})
 conn(b.MouseEnter,function() if active then tween(scale,{Scale=1.035},.15) end end)
 conn(b.MouseLeave,function() if active then tween(scale,{Scale=1},.15) end end)
 return b
end
local roleW=math.floor((PW-29)/2)
local farmerBtn=roleButton('🌲  Фермер',2,roleW)
local killerBtn=roleButton('👹  Убийца',roleW+10,roleW)
caption(killerPage,'👹 Убийца',12,30,16).Font=Enum.Font.GothamBold
caption(killerPage,'Функции для монстра пока не добавлены.\nНажми «РОЛЬ», чтобы вернуться к выбору.',47,76,11)

local tabs=ui('Frame',gamePage,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,32)})
local holder=ui('Frame',gamePage,{BackgroundTransparency=1,Position=UDim2.fromOffset(0,35),
 Size=UDim2.new(1,0,1,-35),ClipsDescendants=true})
local titles={'ESP','Движение','Дерево'}
local pages,tabBtns={},{ }
local tabW=math.floor((PW-23)/3)
for i,txt in ipairs(titles) do
 local j=i
 local b=ui('TextButton',tabs,{Text=txt,Font=Enum.Font.GothamBold,TextSize=11,
 TextColor3=C.muted,BackgroundColor3=C.item,BorderSizePixel=0,
 Position=UDim2.fromOffset((i-1)*(tabW+4),0),Size=UDim2.fromOffset(tabW,29)})
 radius(b,7);tabBtns[i]=b
 local p=ui('ScrollingFrame',holder,{Name='Page'..i,Size=UDim2.fromScale(1,1),
 CanvasSize=UDim2.fromOffset(0,0),BackgroundTransparency=1,
 ScrollBarThickness=2,BorderSizePixel=0,ScrollingDirection=Enum.ScrollingDirection.Y,
 Active=true,Visible=i==1})
 pages[i]=p
 click(b,function()
  for n,page in ipairs(pages) do
   page.Visible=(n==j)
   tween(tabBtns[n],{BackgroundColor3=(n==j and C.blue or C.item)},.13)
   tabBtns[n].TextColor3=(n==j and C.bg or C.muted)
  end
 end)
end
tabBtns[1].BackgroundColor3=C.blue;tabBtns[1].TextColor3=C.bg
local yPos={2,2,2}
local redrawToggles={}
local lastWoodPress=-999
local function rowButton(pageN,title,detail,fn,toggleFlag)
 local parent=pages[pageN]
 local y=yPos[pageN]
 local height=52
 local box=ui('TextButton',parent,{Text='',BackgroundColor3=C.item,BorderSizePixel=0,
 Position=UDim2.fromOffset(2,y),Size=UDim2.new(1,-6,0,height),Active=true})
 radius(box,9)
 local lbl=ui('TextLabel',box,{Text=title,TextColor3=C.text,
 TextSize=12,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,
 BackgroundTransparency=1,Position=UDim2.fromOffset(8,6),
 Size=UDim2.new(1,toggleFlag and -67 or -16,0,19)})
 ui('TextLabel',box,{Text=detail,TextColor3=C.muted,TextSize=10,Font=Enum.Font.Gotham,
 TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true,BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,26),Size=UDim2.new(1,toggleFlag and -67 or -16,0,24)})
 local scale=ui('UIScale',box,{Scale=1})
 local chip
 if toggleFlag then
  chip=ui('TextLabel',box,{Text='ВЫКЛ',Font=Enum.Font.GothamBold,TextSize=10,
   TextColor3=C.text,BackgroundColor3=C.off,BorderSizePixel=0,
   Position=UDim2.new(1,-58,0,13),Size=UDim2.fromOffset(50,25)})
  radius(chip,7)
 end
 local function redraw()
  if chip then
   chip.Text=cfg[toggleFlag] and 'ВКЛ' or 'ВЫКЛ'
   tween(chip,{BackgroundColor3=(cfg[toggleFlag] and C.green or C.off)},.12)
  end
 end
 if toggleFlag then redrawToggles[toggleFlag]=redraw end
 click(box,function()
  tween(scale,{Scale=.965},.09)
  task.delay(.10,function()
   if active and box.Parent then tween(scale,{Scale=1},.16) end
  end)
  if toggleFlag=='wood' then
   local now=os.clock()
   if now-lastWoodPress<.7 then return end
   lastWoodPress=now
  end
  if toggleFlag then cfg[toggleFlag]=not cfg[toggleFlag] end
  redraw()
  fn(lbl)
 end)
 redraw()
 yPos[pageN]=y+height+6
 parent.CanvasSize=UDim2.fromOffset(0,yPos[pageN]+3)
 return box
end
local function hint(pageN,message)
 local parent=pages[pageN]
 ui('TextLabel',parent,{Text=message,TextColor3=C.muted,TextSize=10,
  TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
  Position=UDim2.fromOffset(7,yPos[pageN]+2),Size=UDim2.new(1,-14,0,43),
  BackgroundTransparency=1})
 yPos[pageN]=yPos[pageN]+48
 parent.CanvasSize=UDim2.fromOffset(0,yPos[pageN]+2)
end

local function roleSelect(which)
 stopWood();restoreSpeed();restoreCollision()
 cfg.speed=false;cfg.noclip=false;cfg.esp=false
 for p in pairs(espData) do clearEsp(p) end
 for _,redraw in pairs(redrawToggles) do redraw() end
 role=which=='choose' and nil or which
 rolePage.Visible=which=='choose'
 gamePage.Visible=which=='farmer'
 killerPage.Visible=which=='killer'
 roleChip.Text=(which=='farmer' and 'ФЕРМЕР') or (which=='killer' and 'УБИЙЦА') or 'РОЛЬ'
 status(which=='farmer' and 'Фермер • выбери функцию' or
   which=='killer' and 'Убийца • пока пусто' or 'Выбери роль')
end
click(farmerBtn,function() roleSelect('farmer') end)
click(killerBtn,function() roleSelect('killer') end)
click(roleChip,function() roleSelect('choose') end)

local function updateEsp()
 if not cfg.esp or role~='farmer' then
  for p in pairs(espData) do clearEsp(p) end
  return
 end
 local _,_,me=char()
 local alivePlayers={}
 for _,other in ipairs(Players:GetPlayers()) do
  if other~=LP then
   local c=other.Character
   local hum=c and c:FindFirstChildOfClass('Humanoid')
   local anchor=c and (c:FindFirstChild('Head') or c:FindFirstChild('HumanoidRootPart'))
   if c and hum and anchor and hum.Health>0 then
    local d=espData[other]
    if d and d.char~=c then clearEsp(other);d=nil end
    if not d then
     local hl=ui('Highlight',effects,{Name='DWH19_ESP',Adornee=c,
      DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
      FillTransparency=.98,OutlineTransparency=.14})
     local tag=ui('BillboardGui',PG,{Name='DWH19_PlayerTag',Adornee=anchor,
      AlwaysOnTop=true,MaxDistance=100000,StudsOffset=Vector3.new(0,2.8,0),
      Size=UDim2.fromOffset(112,31),Enabled=true})
     local lab=ui('TextLabel',tag,{Size=UDim2.fromScale(1,1),
      BackgroundColor3=C.bg,BackgroundTransparency=.55,
      TextColor3=C.green,Font=Enum.Font.GothamBold,TextSize=10,
      TextStrokeTransparency=.45,TextWrapped=true,BorderSizePixel=0})
     radius(lab,6)
     d={char=c,highlight=hl,label=lab,items={hl,tag}}
     espData[other]=d
    end
    local dangerous=hum.MaxHealth>100
    local color=dangerous and C.red or C.green
    d.highlight.FillColor=color
    d.highlight.OutlineColor=color
    d.label.TextColor3=color
    local dist=me and math.floor((anchor.Position-me.Position).Magnitude+.5) or nil
    local short=other.DisplayName
    if #short>16 then short=short:sub(1,15)..'…' end
    d.label.Text=(dangerous and '⚠ ' or '')..short..'\n'..
     math.ceil(hum.Health)..' HP'..(dist and (' • '..dist..' ст.') or '')
    alivePlayers[other]=true
   end
  end
 end
 for p in pairs(espData) do if not alivePlayers[p] then clearEsp(p) end end
end

-- Strictly local farming: do not walk across the map or revisit harvested positions.
local words={'tree','trunk','pine','oak','birch','spruce','дерево','ствол'}
local function namedTree(name)
 local n=tostring(name):lower()
 for _,key in ipairs(words) do if n:find(key,1,true) then return true end end
 return false
end
local function visiblePart(p)
 if not p or not p.Parent or not p:IsA('BasePart') then return false end
 return p.Transparency < .94 and p.Size.Magnitude > .5
end
local function trunkPart(obj)
 if not obj or not obj.Parent then return nil end
 if obj:IsA('BasePart') then return visiblePart(obj) and obj or nil end
 if not obj:IsA('Model') then return nil end
 local best,score=nil,-100
 for _,p in ipairs(obj:GetDescendants()) do
  if visiblePart(p) then
   local n=p.Name:lower()
   local value=0
   if n:find('trunk',1,true) or n:find('stem',1,true) or
      n:find('log',1,true) or n:find('ствол',1,true) then value=value+30 end
   if n:find('leaf',1,true) or n:find('branch',1,true) or
      n:find('stump',1,true) or n:find('broken',1,true) then value=value-30 end
   if p.Size.Y>p.Size.X and p.Size.Y>p.Size.Z then value=value+4 end
   if p==obj.PrimaryPart then value=value+1 end
   if value>=0 and value>score then best,score=p,value end
  end
 end
 return best
end
local function treePosition(obj)
 local p=trunkPart(obj)
 return p and p.Position or nil
end
local HP_NAMES={'Health','TreeHealth','WoodHealth','HP'}
local function healthReading(obj)
 if not obj or not obj.Parent then return nil end
 for _,key in ipairs(HP_NAMES) do
  local ok,value=pcall(function()return obj:GetAttribute(key)end)
  if ok and type(value)=='number' then return value end
  local v=obj:FindFirstChild(key)
  if v and (v:IsA('NumberValue') or v:IsA('IntValue')) then return v.Value end
 end
 return nil
end
local function treeAlive(obj)
 if not obj or not obj.Parent then return false end
 local health=healthReading(obj)
 if health and health<=0 then return false end
 return trunkPart(obj)~=nil
end
local function fingerprint(obj)
 -- Detect actual visual destruction (a stump may remain under the same Model).
 if not obj or not obj.Parent then return nil end
 local count=0
 if obj:IsA('BasePart') then count=visiblePart(obj) and 1 or 0
 else
  for _,part in ipairs(obj:GetDescendants()) do
   if visiblePart(part) then count=count+1 end
  end
 end
 return count
end
local function posNear(a,b,maxDist)
 if not a or not b then return false end
 local dx=a.X-b.X;local dz=a.Z-b.Z
 return dx*dx+dz*dz <= maxDist*maxDist
end
local function cleanEmptySpots()
 local t=os.clock()
 for i=#emptySpots,1,-1 do if emptySpots[i].untilTime<=t then table.remove(emptySpots,i) end end
end
local function isEmptySpot(p,obj)
 cleanEmptySpots()
 for _,entry in ipairs(emptySpots) do
  if posNear(entry.pos,p,3.1) and (not obj or entry.ref==obj) then return true end
 end
 return false
end
local function blacklistTree(obj,why)
 local now=os.clock()
 local p=treePosition(obj)
 if obj then woodCooldown[obj]=now+90 end
 if p then emptySpots[#emptySpots+1]={pos=p,ref=obj,untilTime=now+90} end
 if #emptySpots>60 then table.remove(emptySpots,1) end
 farmStatus=why or 'Дерево пропущено'
end
local function scan(force)
 if not force and os.clock()-treeScanAt<4.2 then return end
 treeScanAt=os.clock()
 local seen,found={},{}
 local function consider(obj)
  if not obj or not obj.Parent or #found>=90 then return end
  if obj:IsA('BasePart') and obj.Parent:IsA('Model') and namedTree(obj.Parent.Name) then obj=obj.Parent end
  if seen[obj] or not (obj:IsA('Model') or obj:IsA('BasePart')) then return end
  seen[obj]=true
  if treeAlive(obj) then
   local p=treePosition(obj)
   if p and (not zoneCenter or posNear(p,zoneCenter,ZONE_RADIUS+6)) then
    found[#found+1]=obj
   end
  end
 end
 for _,tag in ipairs({'Tree','ChoppableTree','HarvestableTree'}) do
  local ok,items=pcall(function()return CollectionService:GetTagged(tag)end)
  if ok then for _,obj in ipairs(items) do consider(obj) end end
 end
 -- Light scan (4.2 sec), caching only nearby live-looking trunks.
 local all=workspace:GetDescendants()
 for _,obj in ipairs(all) do
  if #found>=90 then break end
  if (obj:IsA('Model') or obj:IsA('BasePart')) and namedTree(obj.Name) then consider(obj) end
 end
 treeList=found
end
local function nearestTree()
 local _,_,root=char()
 if not root then return nil,nil end
 if not zoneCenter then zoneCenter=root.Position end
 scan(false)
 local best,nearest=nil,MAX_STATIONARY_RANGE+0.01
 local now=os.clock()
 for _,obj in ipairs(treeList) do
  if treeAlive(obj) and (woodCooldown[obj] or 0)<=now then
   local p=treePosition(obj)
   if p and posNear(p,zoneCenter,ZONE_RADIUS) and not isEmptySpot(p,obj) then
    local dx=p.X-root.Position.X;local dz=p.Z-root.Position.Z
    local d=math.sqrt(dx*dx+dz*dz)
    if d<nearest and d<=MAX_STATIONARY_RANGE then
     best,nearest=obj,d
    end
   end
  end
 end
 return best,nearest
end

-- Wood counter is optional; not every version exposes it to client scripts.
-- Only read explicitly named numeric player resources; do not guess from shop labels.
local WOOD_KEYS={'Wood','wood','WoodCount','WoodAmount','Woods'}
local function readWoodValue()
 local list={LP,LP:FindFirstChild('leaderstats'),LP:FindFirstChild('Stats'),LP:FindFirstChild('Data')}
 for _,node in ipairs(list) do
  if node then
   for _,key in ipairs(WOOD_KEYS) do
    local ok,value=pcall(function() return node:GetAttribute(key) end)
    if ok and type(value)=='number' and value>=0 then return value end
    local item=node:FindFirstChild(key)
    if item and (item:IsA('IntValue') or item:IsA('NumberValue')) and item.Value>=0 then
     return item.Value
    end
   end
  end
 end
 return nil
end

local function isSwing(text)
 local s=tostring(text or ''):lower()
 return s:find('swing',1,true) or s:find('качел',1,true) or
  s:find('axe',1,true) or s:find('chop',1,true)
end
local function isForeignGameButton(b)
 if not b or not b.Parent or not b:IsA('GuiButton') or not b.Visible then return false end
 if b:IsDescendantOf(screen) then return false end
 local v=viewport()
 local p=b.AbsolutePosition;local sz=b.AbsoluteSize
 -- Ignore controls outside the right side, e.g. other script windows.
 if p.X<v.X*.47 or sz.X<18 or sz.Y<18 then return false end
 local g=b:FindFirstAncestorWhichIsA('ScreenGui')
 if g and g.Name:find('DeepWoods',1,true) then return false end
 return true
end
local function findSwing()
 if isForeignGameButton(swingButton) then return swingButton end
 if os.clock()-swingScanAt<1.3 then return nil end
 swingScanAt=os.clock()
 swingButton=nil
 local ok,actions=pcall(function()return CAS:GetAllBoundActionInfo()end)
 if ok and type(actions)=='table' then
  for action,info in pairs(actions) do
   if isSwing(action) or (type(info)=='table' and isSwing(info.title)) then
    local yes,b=pcall(function()return CAS:GetButton(action)end)
    if yes and isForeignGameButton(b) then swingButton=b;return b end
   end
  end
 end
 for _,b in ipairs(PG:GetDescendants()) do
  if isForeignGameButton(b) then
   local text=b.Name..' '..(b:IsA('TextButton') and b.Text or '')
   if isSwing(text) then swingButton=b;return b end
   for _,o in ipairs(b:GetDescendants()) do
    if (o:IsA('TextLabel') or o:IsA('TextButton')) and isSwing(o.Text) then
     swingButton=b;return b
    end
   end
  end
 end
 return nil
end
local function signalSwing()
 local b=findSwing()
 if not b then return false,'Не найдена игровая кнопка Swing' end
 if type(firesignal)~='function' then return false,'Delta: firesignal недоступен' end
 local ok=pcall(function() firesignal(b.Activated) end)
 return ok, ok and 'Сигнал Swing' or 'Ошибка firesignal'
end
local function aimTree(pos,hum,root)
 -- Rotate only the character. The player's camera stays fully controllable.
 local facing=Vector3.new(pos.X,root.Position.Y,pos.Z)
 if (facing-root.Position).Magnitude>.25 then
  pcall(function()
   local goal=CFrame.lookAt(root.Position,facing)
   root.CFrame=root.CFrame:Lerp(goal,.68)
  end)
 end
 if not marker then
  marker=ui('Highlight',effects,{Name='DWH22_WoodTarget',
   FillTransparency=.99,OutlineColor=C.blue,OutlineTransparency=.25,
   DepthMode=Enum.HighlightDepthMode.AlwaysOnTop})
 end
 marker.Adornee=woodTarget
end
local function switchTarget(reason,blacklist)
 if woodTarget and blacklist then blacklistTree(woodTarget,reason) end
 woodTarget=nil
 woodHits=0
 woodAttackStarted=0
 woodLastFingerprint=nil
 woodLastHealth=nil
 woodValueAtTarget=nil
 woodSwingsWithoutEffect=0
 woodLastApproachAt=0
 woodLastApproachPos=nil
 stopAim()
 farmStatus=reason or 'Выбираю следующее дерево'
end
local function woodTick()
 local now=os.clock()
 if now<woodNext then return end
 woodNext=now+(fastFarm and FAST_SWING_INTERVAL or SAFE_SWING_INTERVAL)
 local _,hum,root=char()
 if not hum or not root or hum.Health<=0 then stopAim();farmStatus='Ожидаю фермера';return end
 if farmHumanoid~=hum then
  farmHumanoid=hum
  zoneCenter=root.Position
  treeScanAt=-99
  switchTarget('Новый персонаж: зона обновлена',false)
 end
 zoneCenter=root.Position -- only read the position; never move character
 if woodTarget and not treeAlive(woodTarget) then
  switchTarget('Дерево исчезло — следующее',true)
 end
 if not woodTarget then
  woodTarget=nearestTree()
  woodStarted=now;woodAttackStarted=0;woodHits=0
  woodLastApproachAt=now;woodLastApproachPos=root.Position
  woodLastFingerprint=woodTarget and fingerprint(woodTarget) or nil
  woodLastHealth=woodTarget and healthReading(woodTarget) or nil
  woodSwingsWithoutEffect=0
  woodValueAtTarget=woodTarget and readWoodValue() or nil
 end
 if not woodTarget then
  stopAim()
  farmStatus='Рядом (до '..ZONE_RADIUS..' ст.) нет доступных деревьев; стою на месте'
  return
 end
 -- When the server exposes wood as a numeric player resource, any increase
 -- means the previous tree completed. Switch immediately, not after 8 extra swings.
 if woodValueAtTarget~=nil then
  local fresh=readWoodValue()
  if fresh and fresh>woodValueAtTarget then
   switchTarget('Добыто +'..tostring(fresh-woodValueAtTarget)..' древесины • новая цель',true)
   return
  elseif fresh and fresh<woodValueAtTarget then
   woodValueAtTarget=fresh -- external spending shouldn't confuse progression
  end
 end
 local p=treePosition(woodTarget)
 if not p or isEmptySpot(p,woodTarget) or not posNear(p,zoneCenter,ZONE_RADIUS) then
  switchTarget('Старая/недоступная точка — пропущена',true)
  return
 end
 local delta=Vector3.new(p.X-root.Position.X,0,p.Z-root.Position.Z)
 local d=delta.Magnitude
 if d>MAX_STATIONARY_RANGE then
  switchTarget('Дерево вне радиуса: не иду к нему',false)
  return
 end
 -- No MoveTo, pathfinding or teleport. A hit farther than axe reach may be ignored.
 -- If the tree has become invisible, vanished, or lost all health, never swing at air.
 local hp=healthReading(woodTarget)
 local fp=fingerprint(woodTarget)
 if not fp or fp<=0 or (hp and hp<=0) then
  switchTarget('Дерево срублено/пустое — смена цели',true)
  return
 end
 if woodAttackStarted==0 then woodAttackStarted=now end
 pcall(function()aimTree(p,hum,root)end)
 -- Reject an obviously blocked line-of-sight when world raycast is available.
 local origin=root.Position+Vector3.new(0,2.2,0)
 local direction=Vector3.new(p.X,root.Position.Y+2.2,p.Z)-origin
 if direction.Magnitude>0.5 then
  local params=RaycastParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  local ignored={effects}
  if LP.Character then ignored[#ignored+1]=LP.Character end
  params.FilterDescendantsInstances=ignored
  local rayOK,hit=pcall(function()return workspace:Raycast(origin,direction,params)end)
  if rayOK and hit and hit.Instance~=woodTarget and
     not hit.Instance:IsDescendantOf(woodTarget) then
   switchTarget('Удар перекрыт препятствием — другая цель',true)
   return
  end
 end
 local success,why=signalSwing()
 if success then
  woodHits=woodHits+1
  -- Compare state on the following swing; server may respond after a delay.
  if (woodLastHealth and hp and hp<woodLastHealth) or
     (woodLastFingerprint and fp<woodLastFingerprint) then
   woodSwingsWithoutEffect=0
  else
   woodSwingsWithoutEffect=woodSwingsWithoutEffect+1
  end
  woodLastHealth=hp
  woodLastFingerprint=fp
 end
 farmStatus=success and ('Стою • Swing '..woodHits..' | '..math.floor(d+.5)..' ст. | '..(fastFarm and 'быстро' or 'обычно')) or why
 -- Do not farm an old model forever. Cool down position, not only instance ID.
 if (woodSwingsWithoutEffect>=MAX_SWINGS_UNVERIFIED and now-woodAttackStarted>=3.2) or
    now-woodAttackStarted>MAX_ATTACK_TIME then
  switchTarget('Цель без прогресса исключена на 90 сек.',true)
 end
end
local function updateMovement()
 -- Farm never modifies WalkSpeed. The separate manual Speed toggle stays available.
 local _,hum=char()
 if role=='farmer' and cfg.speed and hum then
  if hum~=speedHum then restoreSpeed();speedHum=hum;oldSpeed=hum.WalkSpeed end
  pcall(function()hum.WalkSpeed=walkSpeed end)
 elseif speedHum then restoreSpeed() end
end
local function noclip()
 local c=LP.Character
 if not c then return end
 for _,p in ipairs(c:GetDescendants()) do
  if p:IsA('BasePart') and p.CanCollide then
   if oldCollisions[p]==nil then oldCollisions[p]=p.CanCollide end
   p.CanCollide=false
  end
 end
end
rowButton(1,'ESP игроков','Имя, HP и расстояние. Монстр — красным.',function()
 if not cfg.esp then for p in pairs(espData) do clearEsp(p) end end
 status(cfg.esp and 'ESP включён' or 'ESP выключен')
end,'esp')
hint(1,'Компактные подписи. Дальность максимальная; порог монстра фиксирован: >100 HP.')
rowButton(2,'Быстрый бег','Ускоряет персонажа с выбранной скоростью.',function()
 if not cfg.speed then restoreSpeed() end
 status(cfg.speed and 'Бег включён' or 'Бег выключен')
end,'speed')
rowButton(2,'Скорость: 32','Нажми, чтобы изменить скорость.',function(l)
 local i=table.find(walkChoices,walkSpeed) or 1
 walkSpeed=walkChoices[i%#walkChoices+1]
 l.Text='Скорость: '..walkSpeed
 status('Скорость: '..walkSpeed)
end)
rowButton(2,'Noclip','Проходить через препятствия.',function()
 if not cfg.noclip then restoreCollision() end
 status(cfg.noclip and 'Noclip включён' or 'Noclip выключен')
end,'noclip')
rowButton(3,'Рубка на месте','Не двигается и не блокирует камеру; пробует деревья до 10 студий.',function()
 if cfg.wood then
  local _,_,root=char()
  zoneCenter=root and root.Position or nil
  treeScanAt=-99
  woodNext=0
  scan(true)
 else
  stopWood()
 end
 status(cfg.wood and 'Рубка на месте включена • без ходьбы • Swing' or 'Рубка на месте выключена')
end,'wood')
rowButton(3,'Темп: быстрый','Быстрые удары без перемещения. При пропусках переключи на обычный.',function(label)
 fastFarm=not fastFarm
 label.Text=fastFarm and 'Темп: быстрый' or 'Темп: обычный'
 status(fastFarm and 'Быстрый режим включён' or 'Обычный темп, как в v2.0')
end)
rowButton(3,'Пропустить дерево','Не возвращаться к этой точке 90 секунд.',function()
 switchTarget('Ищу другое дерево',true)
 status('Цель пропущена')
end)
hint(3,'Персонаж стоит. Цели до 10 студий, но сервер может засчитывать удары только в реальной досягаемости топора. Вдалеке нужны данные об игровой механике, а не новые кнопки.')

local function unload()
 if not active then return end
 active=false
 stopWood()
 for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
 restoreSpeed();restoreCollision()
 for p in pairs(espData) do clearEsp(p) end
 pcall(function() effects:Destroy() end)
 pcall(function() screen:Destroy() end)
 for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub19_Unload','DeepWoodsHub20_Unload','DeepWoodsHub21_Unload','DeepWoodsHub211_Unload','DeepWoodsHub22_Unload'}) do
  if env[key]==unload then env[key]=nil end
 end
end
env.DWH_Unload=unload
env.DeepWoodsHub_Unload=unload
env.DeepWoodsHub19_Unload=unload
env.DeepWoodsHub20_Unload=unload
env.DeepWoodsHub21_Unload=unload
env.DeepWoodsHub211_Unload=unload
env.DeepWoodsHub22_Unload=unload
conn(RunService.Stepped,function() if active and role=='farmer' and cfg.noclip then pcall(noclip) end end)
task.spawn(function()
 local espAt=0
 while active do
  task.wait(.18)
  if not active then break end
  local ok,err=pcall(updateMovement)
  if not ok then status('Скорость: '..tostring(err):sub(1,45)) end
  if role=='farmer' and cfg.wood then
   local wok,werr=pcall(woodTick)
   if not wok then farmStatus='Рубка: '..tostring(werr):sub(1,45);stopAim() end
   if os.clock()>=espAt then status(farmStatus) end
  end
  if os.clock()>=espAt then
   espAt=os.clock()+.55
   local eok,eerr=pcall(updateEsp)
   if not eok then status('ESP: '..tostring(eerr):sub(1,54)) end
  end
 end
end)
status('DeepWoods v2.2 • рубка без движения • выбери Фермер')
