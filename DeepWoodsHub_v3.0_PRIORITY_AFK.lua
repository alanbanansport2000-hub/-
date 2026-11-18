-- DeepWoods Hub v3.0 | PRIORITY MULTI-AFK -- near-first active queue, real ChopSwing
-- Based on the user-confirmed v2.5 mechanism:
-- ReplicatedStorage.Remotes.ChopSwing:FireServer(TreeTemplateModel)
-- IMPORTANT: a successful FireServer call is NOT proof that the server awarded wood.
-- No camera changes, forced movement, teleport, remote hooks or GUI Swing clicks.

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')
local ENV = (getgenv and getgenv()) or _G

-- Shut down older farmers before creating the new UI.
for _,key in ipairs({
 'DWH_Unload','DeepWoodsHub_Unload','DWH25_Stop',
 'DeepWoodsHub19_Unload','DeepWoodsHub20_Unload','DeepWoodsHub21_Unload',
 'DeepWoodsHub211_Unload','DeepWoodsHub22_Unload','DeepWoodsHub23_Unload',
 'DeepWoodsHub24_Unload','DeepWoodsHub26_Unload','DeepWoodsHub27_Unload','DeepWoodsHub28_Unload','DeepWoodsHub29_Unload','DeepWoodsHub30_Unload'
}) do
 if type(ENV[key])=='function' then pcall(ENV[key]) end
end
for _,name in ipairs({'DeepWoodsHub_v19_COMPACT','DeepWoodsHub_v20_ANTIGHOST',
 'DeepWoodsHub_v21_FAST_FARM','DeepWoodsHub_v22_STATIONARY',
 'DeepWoodsHub_v23_DUAL','DeepWoodsHub_v24_AFK_VERIFY',
 'DWH25_DirectTree','DWH26_MultiRPC','DWH27_FastRotate','DWH28_RapidAFK','DWH29_TreeFix','DWH30_Focused'}) do
 local old=PG:FindFirstChild(name)
 if old and old:IsA('ScreenGui') then pcall(function() old:Destroy() end) end
end
for _,existing in ipairs(PG:GetChildren()) do
 if existing:IsA('BillboardGui') and (existing.Name=='DWH26_ESPLabel' or existing.Name=='DWH28_ESPLabel') then
  pcall(function()existing:Destroy()end)
 end
end
local oldEffect=workspace:FindFirstChild('DWH26_Effects')
if oldEffect and oldEffect:IsA('Folder') then pcall(function() oldEffect:Destroy() end) end
local old27=workspace:FindFirstChild('DWH27_Effects')
if old27 and old27:IsA('Folder') then pcall(function() old27:Destroy() end) end
local old28=workspace:FindFirstChild('DWH28_Effects')
if old28 and old28:IsA('Folder') then pcall(function() old28:Destroy() end) end
local old29=workspace:FindFirstChild('DWH29_Effects')
if old29 and old29:IsA('Folder') then pcall(function() old29:Destroy() end) end
local old30=workspace:FindFirstChild('DWH30_Effects')
if old30 and old30:IsA('Folder') then pcall(function() old30:Destroy() end) end

local alive=true
local role=nil
local enabled={esp=false,speed=false,noclip=false,farm=false}
local connections={}
local speedChoices={24,32,40,60,90}
local speedIndex=2
local oldSpeedHum,oldSpeed=nil,nil
local oldCollision={}
local esp={}
-- Focus one real tree to completion. Round-robin over dozens of trees spread hits too thin.
local treePool={}
local trunkCache=setmetatable({}, {__mode='k'})
local knownTrees=setmetatable({}, {__mode='k'})
local treePenalty=setmetatable({}, {__mode='k'})
local nextTreeScan=-10
local fullTreeScanAt=-10
local poolDirty=true
local treeScanStats={all=0,near=0,valid=0,hpZero=0,noVisible=0,otherNames=0,closest=nil,lastAt=-100}
local treeNextSend=setmetatable({}, {__mode='k'})
local treeAttempts=setmetatable({}, {__mode='k'})
local treeCursor=0
local lastSentTarget=nil
local lastSentAt=-10
local currentDistance=nil
local priorityNearCount=0
local farFailures=0
local farPauseUntil=0
local lastChar=nil
-- Search radius, not a promise of server reach. 10 is user-observed reliable.
local radiusValues={10,20,35}
local radiusIndex=1
local modes={
 {label='Обычный',rps=4,spacing=.48,burst=1,maxHits=8},
 {label='Быстрый',rps=10,spacing=.32,burst=2,maxHits=9},
 {label='MAX',rps=18,spacing=.30,burst=3,maxHits=9},
 {label='Тест',rps=24,spacing=.24,burst=4,maxHits=10},
}
local modeIndex=3
local remote=nil
local lastFarmTick=-10
local requestTokens=2
local totalSent,totalErrors,totalWood=0,0,0
local lastWood=nil
local woodSource='не найден'
local lastWoodCheck=-10
local pendingCreditTarget=nil
local pendingCredit=0
local farmStart=nil
local lastWoodProgress=0
local lastFarmMessage='AFK выключен'
local uiMessage='Выбери роль'
local lastUiUpdate=-10
local lastScanCause='не проверял'

local targetsCredited=0
local targetsNoCredit=0


local COLOR={
 bg=Color3.fromRGB(14,19,30),panel=Color3.fromRGB(23,32,47),
 card=Color3.fromRGB(36,47,64),accent=Color3.fromRGB(78,193,230),
 text=Color3.fromRGB(238,245,251),muted=Color3.fromRGB(166,187,205),
 green=Color3.fromRGB(51,205,151),red=Color3.fromRGB(245,94,107),
 off=Color3.fromRGB(77,91,108)
}
local function subscribe(signal,fn)
 local c=signal:Connect(fn)
 connections[#connections+1]=c
 return c
end
local function make(kind,parent,props)
 local item=Instance.new(kind)
 for key,val in pairs(props or {}) do
  assert(type(key)=='string','Invalid property key '..tostring(key))
  item[key]=val
 end
 item.Parent=parent
 return item
end
local function rounded(obj,px)
 make('UICorner',obj,{CornerRadius=UDim.new(0,px or 9)})
end
local function animate(obj,props,t)
 local ok=pcall(function()
  TweenService:Create(obj,TweenInfo.new(t or .18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),props):Play()
 end)
 if not ok then for k,v in pairs(props) do pcall(function()obj[k]=v end)end end
end
local function char()
 local c=LP.Character
 return c,c and c:FindFirstChildOfClass('Humanoid'),c and c:FindFirstChild('HumanoidRootPart')
end
local function view()
 local cam=workspace.CurrentCamera
 return cam and cam.ViewportSize or Vector2.new(790,440)
end
local function restoreSpeed()
 if oldSpeedHum and oldSpeedHum.Parent and oldSpeed~=nil then
  pcall(function()oldSpeedHum.WalkSpeed=oldSpeed end)
 end
 oldSpeedHum,oldSpeed=nil,nil
end
local function restoreCollision()
 for p,original in pairs(oldCollision) do
  if p and p.Parent then pcall(function()p.CanCollide=original end)end
 end
 oldCollision={}
end
local function clearEsp(other)
 local d=esp[other]
 if not d then return end
 for _,item in ipairs(d.items) do pcall(function()item:Destroy()end)end
 esp[other]=nil
end

local screen=make('ScreenGui',PG,{Name='DWH30_Focused',IgnoreGuiInset=true,
 ResetOnSpawn=false,DisplayOrder=975,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local effectFolder=make('Folder',workspace,{Name='DWH30_Effects'})
local v=view()
local PW=math.min(300,math.max(230,v.X-18))
local PH=math.min(267,math.max(210,v.Y-24))
local panel=make('Frame',screen,{Name='Window',BackgroundColor3=COLOR.bg,
 BorderSizePixel=0,Active=true,ClipsDescendants=true,
 Size=UDim2.fromOffset(PW,PH),Position=UDim2.fromOffset(
 math.max(9,math.floor((v.X-PW)/2)),math.max(12,math.floor((v.Y-PH)/2)))})
rounded(panel,14)
make('UIStroke',panel,{Color=COLOR.accent,Thickness=1.2,Transparency=.2})
local panelScale=make('UIScale',panel,{Scale=.94})
local top=make('Frame',panel,{BackgroundColor3=COLOR.panel,BorderSizePixel=0,
 Size=UDim2.new(1,0,0,37),Active=true})
rounded(top,12)
local handle=make('TextButton',top,{Text='🌲 DeepWoods 3.0',Font=Enum.Font.GothamBold,
 TextColor3=COLOR.text,TextXAlignment=Enum.TextXAlignment.Left,TextSize=12,
 Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-139,1,0),
 BackgroundTransparency=1,AutoButtonColor=false,Active=true})
local roleChip=make('TextButton',top,{Text='РОЛЬ',Font=Enum.Font.GothamBold,
 TextColor3=COLOR.muted,TextSize=10,BackgroundColor3=COLOR.card,
 BorderSizePixel=0,Position=UDim2.new(1,-117,0,7),Size=UDim2.fromOffset(70,23)})
rounded(roleChip,7)
local mini=make('TextButton',top,{Text='−',Font=Enum.Font.GothamBold,
 TextColor3=COLOR.text,TextSize=20,BackgroundColor3=COLOR.card,
 BorderSizePixel=0,Position=UDim2.new(1,-36,0,5),Size=UDim2.fromOffset(29,27)})
rounded(mini,7)
local bubble=make('TextButton',screen,{Text='🌲',Name='FloatingIcon',
 Font=Enum.Font.GothamBold,TextSize=23,TextColor3=COLOR.text,
 BackgroundColor3=COLOR.panel,BorderSizePixel=0,Active=true,
 Position=UDim2.fromOffset(15,math.floor((v.Y-45)/2)),
 Size=UDim2.fromOffset(45,45),Visible=false,ZIndex=20})
rounded(bubble,13)
make('UIStroke',bubble,{Color=COLOR.accent,Thickness=1.5})
local foot=make('TextLabel',panel,{Text=uiMessage,Font=Enum.Font.Gotham,
 TextColor3=COLOR.muted,TextSize=10,TextWrapped=true,
 BackgroundColor3=COLOR.panel,TextXAlignment=Enum.TextXAlignment.Center,
 BorderSizePixel=0,Position=UDim2.new(0,8,1,-29),Size=UDim2.new(1,-16,0,24)})
rounded(foot,7)
local function status(msg)
 uiMessage=tostring(msg)
 if alive and foot.Parent then foot.Text=uiMessage end
end
local function pressed(button,fn)
 local last=-100
 subscribe(button.Activated,function()
  if not alive or os.clock()-last<.24 then return end
  last=os.clock()
  local ok,err=pcall(fn)
  if not ok then status('Кнопка: '..tostring(err):sub(1,75)) end
 end)
end
-- Drag keeps its originating touch, and respects viewport boundaries.
local bubbleMoved=false
local bubbleTapBlocked=0
local function draggable(surface,target,isBubble)
 local inputStart,mouseStart,origin=nil,nil,nil
 local moved=false
 local function move(inp)
  if not inputStart then return end
  if inputStart.UserInputType==Enum.UserInputType.Touch then
   if inp~=inputStart then return end
  elseif inp.UserInputType~=Enum.UserInputType.MouseMovement and inp~=inputStart then return end
  local delta=inp.Position-mouseStart
  if delta.Magnitude>=7 then moved=true end
  if not moved then return end
  local bounds=view()
  local x=math.clamp(origin.X.Offset+delta.X,12,math.max(12,bounds.X-target.AbsoluteSize.X-12))
  local y=math.clamp(origin.Y.Offset+delta.Y,15,math.max(15,bounds.Y-target.AbsoluteSize.Y-15))
  target.Position=UDim2.fromOffset(x,y)
  if isBubble then bubbleMoved=true;bubbleTapBlocked=os.clock()+.4 end
 end
 subscribe(surface.InputBegan,function(inp)
  if inputStart then return end
  if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
   inputStart=inp;mouseStart=inp.Position;origin=target.Position;moved=false
  end
 end)
 subscribe(surface.InputChanged,move)
 subscribe(UserInputService.InputChanged,move)
 local function finish(inp)
  if inputStart and (inp==inputStart or (inputStart.UserInputType==Enum.UserInputType.MouseButton1
    and inp.UserInputType==Enum.UserInputType.MouseButton1)) then
   if isBubble and moved then bubbleTapBlocked=os.clock()+.4 end
   inputStart=nil;mouseStart=nil;origin=nil
  end
 end
 subscribe(surface.InputEnded,finish)
 subscribe(UserInputService.InputEnded,finish)
end
draggable(handle,panel,false)
draggable(bubble,bubble,true)
local function shrink()
 local size=view()
 if not bubbleMoved then bubble.Position=UDim2.fromOffset(14,math.floor((size.Y-45)/2))end
 bubble.Position=UDim2.fromOffset(
  math.clamp(bubble.Position.X.Offset,12,math.max(12,size.X-57)),
  math.clamp(bubble.Position.Y.Offset,15,math.max(15,size.Y-60)))
 panel.Visible=false
 bubble.Size=UDim2.fromOffset(34,34)
 bubble.Visible=true
 animate(bubble,{Size=UDim2.fromOffset(45,45)},.22)
end
local function expand()
 local size=view()
 local x=math.clamp(bubble.Position.X.Offset,9,math.max(9,size.X-PW-9))
 local y=math.clamp(bubble.Position.Y.Offset,12,math.max(12,size.Y-PH-12))
 panel.Position=UDim2.fromOffset(x,y)
 bubble.Visible=false
 panel.Visible=true
 panelScale.Scale=.90
 animate(panelScale,{Scale=1},.23)
end
pressed(mini,shrink)
pressed(bubble,function()if os.clock()>=bubbleTapBlocked then expand()end end)
animate(panelScale,{Scale=1},.29)

local rolePage=make('Frame',panel,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,43),Size=UDim2.new(1,-16,1,-78)})
local farmerPage=make('Frame',panel,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,43),Size=UDim2.new(1,-16,1,-78),Visible=false})
local killerPage=make('Frame',panel,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(8,43),Size=UDim2.new(1,-16,1,-78),Visible=false})
local function caption(parent,txt,y,height,fontSize)
 return make('TextLabel',parent,{Text=txt,Font=Enum.Font.Gotham,
 TextSize=fontSize or 12,TextWrapped=true,TextColor3=COLOR.muted,
 BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Center,
 Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,height)})
end
caption(rolePage,'Выбери роль',11,28,16).Font=Enum.Font.GothamBold
caption(rolePage,'Скрипт покажет функции выбранной стороны',41,32,11)
local btnW=math.floor((PW-34)/2)
local farmerBtn=make('TextButton',rolePage,{Text='🌲 Фермер',Font=Enum.Font.GothamBold,
 TextColor3=COLOR.text,TextSize=13,BackgroundColor3=COLOR.card,BorderSizePixel=0,
 Position=UDim2.new(0,4,.59,0),Size=UDim2.fromOffset(btnW,55)})
local killerBtn=make('TextButton',rolePage,{Text='👹 Убийца',Font=Enum.Font.GothamBold,
 TextColor3=COLOR.text,TextSize=13,BackgroundColor3=COLOR.card,BorderSizePixel=0,
 Position=UDim2.new(0,btnW+12,.59,0),Size=UDim2.fromOffset(btnW,55)})
rounded(farmerBtn,10);rounded(killerBtn,10)
caption(killerPage,'👹 Убийца',17,38,16).Font=Enum.Font.GothamBold
caption(killerPage,'Функции убийцы пока не добавлены.\nКнопка «РОЛЬ» вернёт к выбору.',57,69,12)

local tabBar=make('Frame',farmerPage,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,32)})
local holder=make('Frame',farmerPage,{BackgroundTransparency=1,
 Position=UDim2.fromOffset(0,35),Size=UDim2.new(1,0,1,-35),ClipsDescendants=true})
local tabs={}
local pages={}
local y={3,3,3}
local toggleDraw={}
local titles={'ESP','Движение','Дерево'}
local tabW=math.floor((PW-23)/3)
local function showTab(index)
 for i,p in ipairs(pages) do
  p.Visible=i==index
  animate(tabs[i],{BackgroundColor3=(i==index and COLOR.accent or COLOR.card)},.18)
  tabs[i].TextColor3=i==index and COLOR.bg or COLOR.muted
 end
end
for i,txt in ipairs(titles) do
 local at=i
 tabs[i]=make('TextButton',tabBar,{Text=txt,Font=Enum.Font.GothamBold,
 TextColor3=COLOR.muted,TextSize=11,BackgroundColor3=COLOR.card,
 BorderSizePixel=0,Position=UDim2.fromOffset((i-1)*(tabW+4),0),
 Size=UDim2.fromOffset(tabW,30)})
 rounded(tabs[i],7)
 pages[i]=make('ScrollingFrame',holder,{Name='Tab'..i,BackgroundTransparency=1,
 BorderSizePixel=0,ScrollBarThickness=2,ScrollingDirection=Enum.ScrollingDirection.Y,
 CanvasSize=UDim2.fromOffset(0,0),Size=UDim2.fromScale(1,1),Visible=i==1,Active=true})
 pressed(tabs[i],function()showTab(at)end)
end
tabs[1].BackgroundColor3=COLOR.accent;tabs[1].TextColor3=COLOR.bg
local function row(which,title,detail,callback,flag)
 local parent=pages[which]
 local h=50
 local b=make('TextButton',parent,{Text='',BackgroundColor3=COLOR.card,
 BorderSizePixel=0,Position=UDim2.fromOffset(3,y[which]),
 Size=UDim2.new(1,-8,0,h),Active=true})
 rounded(b,9)
 local label=make('TextLabel',b,{Text=title,Font=Enum.Font.GothamBold,
 TextColor3=COLOR.text,TextXAlignment=Enum.TextXAlignment.Left,TextSize=12,
 BackgroundTransparency=1,Position=UDim2.fromOffset(9,4),
 Size=UDim2.new(1,flag and -70 or -18,0,22)})
 make('TextLabel',b,{Text=detail,Font=Enum.Font.Gotham,TextSize=10,
 TextColor3=COLOR.muted,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
 BackgroundTransparency=1,Position=UDim2.fromOffset(9,25),
 Size=UDim2.new(1,flag and -70 or -18,0,24)})
 local chip
 if flag then
  chip=make('TextLabel',b,{Text='ВЫКЛ',Font=Enum.Font.GothamBold,TextSize=10,
   TextColor3=COLOR.text,BackgroundColor3=COLOR.off,BorderSizePixel=0,
   Position=UDim2.new(1,-57,0,12),Size=UDim2.fromOffset(50,25)})
  rounded(chip,7)
 end
 local function draw()
  if chip then
   chip.Text=enabled[flag] and 'ВКЛ' or 'ВЫКЛ'
   animate(chip,{BackgroundColor3=enabled[flag] and COLOR.green or COLOR.off},.17)
  end
 end
 if flag then toggleDraw[flag]=draw end
 pressed(b,function()
  if flag then enabled[flag]=not enabled[flag] end
  draw()
  animate(b,{BackgroundColor3=COLOR.panel},.09)
  task.delay(.10,function()if alive and b.Parent then animate(b,{BackgroundColor3=COLOR.card},.2)end end)
  callback(label)
 end)
 y[which]=y[which]+h+7
 parent.CanvasSize=UDim2.fromOffset(0,y[which]+5)
 draw()
 return b
end
local function hint(which,txt)
 local p=pages[which]
 make('TextLabel',p,{Text=txt,Font=Enum.Font.Gotham,
 TextColor3=COLOR.muted,TextSize=10,TextWrapped=true,
 TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
 BackgroundTransparency=1,Position=UDim2.fromOffset(8,y[which]+2),
 Size=UDim2.new(1,-16,0,55)})
 y[which]=y[which]+61
 p.CanvasSize=UDim2.fromOffset(0,y[which]+2)
end

local function stopFarm()
 enabled.farm=false
 lastFarmMessage='AFK выключен'
 treePool={}
 lastSentTarget=nil;currentDistance=nil
 pendingCreditTarget=nil;pendingCredit=0
 requestTokens=0;treeCursor=0
 farmStart=nil
 if toggleDraw.farm then toggleDraw.farm() end
end
local function chooseRole(nextRole)
 stopFarm()
 restoreSpeed();restoreCollision()
 enabled.esp=false;enabled.speed=false;enabled.noclip=false
 for p in pairs(esp) do clearEsp(p) end
 for _,draw in pairs(toggleDraw) do draw() end
 role=nextRole=='choose' and nil or nextRole
 rolePage.Visible=nextRole=='choose'
 farmerPage.Visible=nextRole=='farmer'
 killerPage.Visible=nextRole=='killer'
 roleChip.Text=nextRole=='farmer' and 'ФЕРМЕР' or
  (nextRole=='killer' and 'УБИЙЦА' or 'РОЛЬ')
 status(nextRole=='farmer' and 'Фермер • выбери функцию' or
  (nextRole=='killer' and 'Убийца • пока пусто' or 'Выбери роль'))
 if nextRole=='farmer' then showTab(3) end
end
pressed(farmerBtn,function()chooseRole('farmer')end)
pressed(killerBtn,function()chooseRole('killer')end)
pressed(roleChip,function()chooseRole('choose')end)

-- Lightweight ESP updates. Role estimation uses MaxHealth > 100 only.
local function refreshESP()
 if not enabled.esp or role~='farmer' then
  for p in pairs(esp) do clearEsp(p) end
  return
 end
 local _,_,root=char()
 local seen={}
 for _,other in ipairs(Players:GetPlayers()) do
  if other~=LP then
   local c=other.Character
   local hum=c and c:FindFirstChildOfClass('Humanoid')
   local head=c and (c:FindFirstChild('Head') or c:FindFirstChild('HumanoidRootPart'))
   if c and hum and head and hum.Health>0 then
    local d=esp[other]
    if d and d.character~=c then clearEsp(other);d=nil end
    if not d then
     local hl=make('Highlight',effectFolder,{Adornee=c,
      DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
      FillTransparency=.985,OutlineTransparency=.23})
     local tag=make('BillboardGui',PG,{Adornee=head,Name='DWH29_ESPLabel',
      AlwaysOnTop=true,MaxDistance=100000,StudsOffset=Vector3.new(0,2.6,0),
      Size=UDim2.fromOffset(117,31)})
     local label=make('TextLabel',tag,{Size=UDim2.fromScale(1,1),
      Font=Enum.Font.GothamBold,TextSize=10,TextWrapped=true,
      BackgroundColor3=COLOR.bg,BackgroundTransparency=.55,
      TextColor3=COLOR.green,TextStrokeTransparency=.5,BorderSizePixel=0})
     rounded(label,6)
     d={character=c,label=label,hl=hl,items={hl,tag}}
     esp[other]=d
    end
    local danger=hum.MaxHealth>100
    local col=danger and COLOR.red or COLOR.green
    d.hl.FillColor=col;d.hl.OutlineColor=col;d.label.TextColor3=col
    local dist=root and math.floor((head.Position-root.Position).Magnitude+.5) or nil
    local name=other.DisplayName
    if #name>16 then name=name:sub(1,15)..'…' end
    d.label.Text=(danger and '⚠ ' or '')..name..'\n'..
      math.ceil(hum.Health)..' HP'..(dist and (' · '..dist..' ст.') or '')
    seen[other]=true
   end
  end
 end
 for p in pairs(esp) do if not seen[p] then clearEsp(p)end end
end

local function updateMovement()
 local _,hum=char()
 if role=='farmer' and enabled.speed and hum then
  if hum~=oldSpeedHum then restoreSpeed();oldSpeedHum=hum;oldSpeed=hum.WalkSpeed end
  pcall(function()hum.WalkSpeed=speedChoices[speedIndex] end)
 elseif oldSpeedHum then restoreSpeed()end
end
local function noclip()
 local c=LP.Character
 if not c then return end
 for _,p in ipairs(c:GetDescendants()) do
  if p:IsA('BasePart') and p.CanCollide then
   if oldCollision[p]==nil then oldCollision[p]=p.CanCollide end
   p.CanCollide=false
  end
 end
end

-- v2.5-confirmed: ReplicatedStorage.Remotes.ChopSwing:FireServer(Model:TreeTemplate)
-- Never move the player, rotate the camera or forge a successful wood gain.
local function characterRoot()
 local _,hum,root=char()
 if not root or not hum or hum.Health<=0 then return nil end
 return root
end
local function treeTrunk(model)
 if not model or not model.Parent or not model:IsA('Model') or model.Name~='TreeTemplate' then return nil end
 local cached=trunkCache[model]
 if cached and cached.Parent and cached.Transparency<.95 and cached.Size.Magnitude>1.5 then return cached end
 local best,bestScore=nil,-999
 for _,p in ipairs(model:GetDescendants()) do
  if p:IsA('BasePart') and p.Transparency<.95 and p.Size.Magnitude>1.5 then
   local n=p.Name:lower()
   local score=1
   if n:find('trunk',1,true) or n:find('stem',1,true) or n:find('log',1,true) or n:find('ствол',1,true) then score=30 end
   if n:find('leaf',1,true) or n:find('branch',1,true) then score=-20 end
   if score>bestScore then best,bestScore=p,score end
  end
 end
 trunkCache[model]=best
 return best
end
local function treeAlive(model)
 if not model or not model.Parent or model.Name~='TreeTemplate' then return false end
 for _,key in ipairs({'Health','TreeHealth','WoodHealth','HP'}) do
  local ok,hp=pcall(function()return model:GetAttribute(key)end)
  if ok and type(hp)=='number' and hp<=0 then return false end
  local v=model:FindFirstChild(key)
  if v and (v:IsA('NumberValue') or v:IsA('IntValue')) and v.Value<=0 then return false end
 end
 return treeTrunk(model)~=nil
end
local function distance(root,model)
 local part=treeTrunk(model)
 if not part then return math.huge end
 local dx=part.Position.X-root.Position.X
 local dz=part.Position.Z-root.Position.Z
 return math.sqrt(dx*dx+dz*dz)
end
-- Full world traversal is rare. DescendantAdded/Removing handles normal respawns.
-- Frequent lightweight rescans of the known Model list handle same-instance regrowth.
local function scanTrees(force)
 local now=os.clock()
 if not force and not poolDirty and now<nextTreeScan then return end
 if force or now>=fullTreeScanAt then
  for _,obj in ipairs(workspace:GetDescendants()) do
   if obj:IsA('Model') and obj.Name=='TreeTemplate' then knownTrees[obj]=true end
  end
  fullTreeScanAt=now+((#treePool==0) and 3.2 or 7.5)
  lastScanCause='полный'
 else
  lastScanCause='индекс'
 end
 poolDirty=false
 local root=characterRoot()
 local found={}
 local stats={all=0,near=0,valid=0,hpZero=0,noVisible=0,otherNames=0,closest=nil,lastAt=now}
 if root then
  local range=radiusValues[radiusIndex]
  for obj in pairs(knownTrees) do
   if obj.Parent then
    stats.all=stats.all+1
    local p=treeTrunk(obj)
    if p then
     local dx=p.Position.X-root.Position.X
     local dz=p.Position.Z-root.Position.Z
     local d=math.sqrt(dx*dx+dz*dz)
     if not stats.closest or d<stats.closest then stats.closest=d end
     if d<=range then
      stats.near=stats.near+1
      if treeAlive(obj) then
       found[#found+1]={ref=obj,dist=d}
       stats.valid=stats.valid+1
      else
       stats.hpZero=stats.hpZero+1
      end
     end
    else
     stats.noVisible=stats.noVisible+1
    end
   else
    knownTrees[obj]=nil
   end
  end
  table.sort(found,function(a,b)return a.dist<b.dist end)
 end
 treeScanStats=stats
 treePool=found
 -- When no trees exist, check known objects more frequently but avoid huge scans.
 nextTreeScan=now+(#found>0 and .65 or .40)
end

-- Pick from the closest valid live models. When near trees exist, NEVER let
-- distant speculative requests consume their RPC budget. Multiple close
-- trees can be chopped concurrently, each with its own server pacing.
local function pickTarget(root,used,now)
 local near,far={},{}
 local maxRange=radiusValues[radiusIndex]
 local haveNear=false
 for _,entry in ipairs(treePool) do
  local model=entry.ref
  if model and treeAlive(model) then
   local d=distance(root,model)
   if d<=maxRange then
    if d<=10 then
     haveNear=true
     if (treePenalty[model] or 0)<=now then near[#near+1]={ref=model,dist=d} end
    elseif (treePenalty[model] or 0)<=now then
     far[#far+1]={ref=model,dist=d}
    end
   end
  end
 end
 priorityNearCount=#near
 -- If near trees are on short cooldown, do not waste time on out-of-reach ones.
 if haveNear and #near==0 then return nil,nil end
 local pool=(#near>0) and near or far
 if #pool==0 then return nil,nil end
 if #near==0 and now<farPauseUntil then return nil,nil end
 -- Nearby = up to 10 simultaneous trees; farther = 2 test targets max.
 local count=math.min(#near>0 and 10 or 2,#pool)
 for _=1,count do
  treeCursor=treeCursor%count+1
  local entry=pool[treeCursor]
  local t=entry.ref
  if not used[t] and (treeNextSend[t] or 0)<=now then return t,entry.dist end
 end
 return nil,nil
end
local WOOD_NAMES={'Wood','wood','WoodCount','WoodAmount','Woods','Древесина'}
local function readWood()
 local nodes={LP,LP:FindFirstChild('leaderstats'),LP:FindFirstChild('Stats'),LP:FindFirstChild('Data')}
 for _,node in ipairs(nodes) do
  if node then
   for _,key in ipairs(WOOD_NAMES) do
    local ok,n=pcall(function()return node:GetAttribute(key)end)
    if ok and type(n)=='number' and n>=0 then return n,'attribute:'..node.Name..'/'..key end
    local item=node:FindFirstChild(key)
    if item and (item:IsA('IntValue') or item:IsA('NumberValue')) and item.Value>=0 then
     return item.Value,'value:'..node.Name..'/'..key
    end
   end
  end
 end
 return nil,'недоступен'
end
local function pollWood(force)
 local now=os.clock()
 if not force and now-lastWoodCheck<.11 then return end
 lastWoodCheck=now
 local amount,src=readWood()
 if amount~=nil then
  if lastWood~=nil and amount>lastWood then
   local diff=amount-lastWood
   totalWood=totalWood+diff
   lastWoodProgress=now
   if lastSentTarget and now-lastSentAt<=1.3 then
    pendingCreditTarget=lastSentTarget
    pendingCredit=pendingCredit+diff
   end
  end
  lastWood=amount
  woodSource=src
 end
end
local function getRemote()
 if remote and remote.Parent then return remote end
 local folder=RS:FindFirstChild('Remotes')
 local r=folder and folder:FindFirstChild('ChopSwing')
 if r and r:IsA('RemoteEvent') then remote=r;return remote end
 return nil
end
local function fireTree(t)
 local r=getRemote()
 if not r then return false,'Нет ChopSwing' end
 if not treeAlive(t) then return false,'Дерево отсутствует' end
 local ok,err=pcall(function()r:FireServer(t)end)
 if ok then totalSent=totalSent+1 else totalErrors=totalErrors+1 end
 return ok,ok and 'RPC отправлен' or tostring(err)
end
local function report()
 pollWood(true)
 local elapsed=farmStart and math.max(0,os.clock()-farmStart) or 0
 local rate=elapsed>0 and (totalWood/elapsed*60) or 0
 return 'DeepWoods 3.0 | AFK='..(enabled.farm and 'ВКЛ' or 'ВЫКЛ')..
  ' | поиск='..radiusValues[radiusIndex]..' ст.'..
  ' | темп='..modes[modeIndex].label..
  ' | моделей='..treeScanStats.all..' | рядом='..treeScanStats.near..
  ' | доступно='..treeScanStats.valid..' | ближних='..priorityNearCount..
  ' | RPC='..totalSent..' | ошибок='..totalErrors..
  ' | добыто +'..(lastWood and totalWood or '?')..
  ' | деревьев с наградой≈'..targetsCredited..
  ' | без награды='..targetsNoCredit..
  ' | древесина/мин='..math.floor(rate+.5)..' | источник='..woodSource
end
-- Token bucket + per-tree throttle, but NO global cooldown and NO far-tree
-- starvation of near trees. All sends go through the user-confirmed RPC.
local function doFarm(now)
 if not enabled.farm or role~='farmer' then return end
 local root=characterRoot()
 if not root then lastFarmMessage='Жду фермера';return end
 if LP.Character~=lastChar then
  lastChar=LP.Character
  poolDirty=true;nextTreeScan=-10;fullTreeScanAt=-10
  treeNextSend=setmetatable({}, {__mode='k'})
  treeAttempts=setmetatable({}, {__mode='k'})
  treePenalty=setmetatable({}, {__mode='k'})
  farFailures=0;farPauseUntil=0
  lastSentTarget=nil;currentDistance=nil
 end
 if not getRemote() then lastFarmMessage='ChopSwing не найден';return end
 pollWood(false)
 if pendingCreditTarget then
  local t=pendingCreditTarget
  treePenalty[t]=now+.85
  treeAttempts[t]=0
  farFailures=0
  targetsCredited=targetsCredited+1
  pendingCreditTarget=nil;pendingCredit=0
 end
 scanTrees(false)
 local mode=modes[modeIndex]
 local dt=math.max(0,math.min(.20,now-lastFarmTick))
 lastFarmTick=now
 requestTokens=math.min(mode.burst,requestTokens+dt*mode.rps)
 local allowance=math.min(mode.burst,math.floor(requestTokens))
 if allowance<1 then return end
 local used={}
 local count=0
 for _=1,allowance do
  local model,d=pickTarget(root,used,now)
  if not model then break end
  used[model]=true
  requestTokens=requestTokens-1
  treeNextSend[model]=now+mode.spacing
  local ok,why=fireTree(model)
  if ok then
   count=count+1
   local calls=(treeAttempts[model] or 0)+1
   treeAttempts[model]=calls
   lastSentTarget=model;lastSentAt=now;currentDistance=d
   if calls>=mode.maxHits then
    treeAttempts[model]=0
    -- Far failed targets have long backoff. Near ones retry quickly.
    treePenalty[model]=now+((d>10) and 7.5 or .55)
    if d>10 then
     farFailures=farFailures+1
     if farFailures>=2 then farPauseUntil=now+12;farFailures=0 end
    end
    targetsNoCredit=targetsNoCredit+1
   end
  else
   treePenalty[model]=now+1.0
   lastFarmMessage=why
  end
 end
 if count>0 then
  lastFarmMessage='RPC +'..count..' | ближних '..priorityNearCount..' | '..mode.label
 elseif #treePool>0 then
  lastFarmMessage='Цели ожидают отката серверного удара (без общей паузы)'
 else
  lastFarmMessage='Не найдено целых деревьев в радиусе '..radiusValues[radiusIndex]
 end
 if lastWood and totalSent>20 and now-lastWoodProgress>12 then
  lastFarmMessage='RPC есть, но древесина не растёт — проверь серверную дальность'
 end
end

row(1,'ESP игроков','Компактные подписи, HP и расстояние; монстр красным.',function()
 if not enabled.esp then for p in pairs(esp) do clearEsp(p)end end
 status(enabled.esp and 'ESP включён' or 'ESP выключен')
end,'esp')
hint(1,'Монстр определяется предположительно: MaxHealth > 100. Дальность ESP максимальная.')
row(2,'Быстрый бег','Выбрать дополнительную скорость игрока.',function()
 if not enabled.speed then restoreSpeed()end
 status(enabled.speed and 'Быстрый бег включён' or 'Быстрый бег выключен')
end,'speed')
row(2,'Скорость: 32','Цикл 24 / 32 / 40 / 60 / 90.',function(label)
 speedIndex=speedIndex%#speedChoices+1
 label.Text='Скорость: '..speedChoices[speedIndex]
 status('Скорость '..speedChoices[speedIndex])
end)
row(2,'Noclip','Проходить сквозь препятствия.',function()
 if not enabled.noclip then restoreCollision()end
 status(enabled.noclip and 'Noclip включён' or 'Noclip выключен')
end,'noclip')
row(3,'AFK: прямая рубка','Стою на месте; быстро обрабатываю ближайшие деревья вместе.',function()
 if enabled.farm then
  if not getRemote() then
   enabled.farm=false
   if toggleDraw.farm then toggleDraw.farm() end
   status('ChopSwing отсутствует: войди в матч за фермера')
   return
  end
  poolDirty=true;nextTreeScan=-10;fullTreeScanAt=-10;lastFarmTick=os.clock()
  requestTokens=2;treeCursor=0;lastSentTarget=nil;currentDistance=nil
  treePenalty=setmetatable({}, {__mode='k'})
  treeNextSend=setmetatable({}, {__mode='k'})
  treeAttempts=setmetatable({}, {__mode='k'})
  pendingCreditTarget=nil;pendingCredit=0
  farmStart=os.clock();totalSent,totalErrors,totalWood=0,0,0
  lastWood=nil;lastWoodCheck=-10;pollWood(true)
  lastWoodProgress=os.clock()
  targetsCredited=0;targetsNoCredit=0
  lastChar=LP.Character
  scanTrees(true)
  status('AFK включён: ближние первыми, без ходьбы')
 else
  stopFarm()
  status('AFK выключен')
 end
end,'farm')
row(3,'Радиус: 10 ст.','Поиск 10 / 20 / 35. Дальний запрос не означает награду.',function(label)
 radiusIndex=radiusIndex%#radiusValues+1
 label.Text='Радиус: '..radiusValues[radiusIndex]..' ст.'
 nextTreeScan=-10;poolDirty=true
 lastSentTarget=nil;currentDistance=nil;treeCursor=0
 status('Поиск '..radiusValues[radiusIndex]..' ст. (лимит сервера может быть меньше)')
end)
row(3,'Темп: MAX','Обычный / Быстрый / MAX / Тест; бьёт одну цель до добычи.',function(label)
 modeIndex=modeIndex%#modes+1
 label.Text='Темп: '..modes[modeIndex].label
 status('Темп '..modes[modeIndex].label..'; до '..modes[modeIndex].rps..' RPC/с')
end)
row(3,'Проверить деревья','Пересканировать объекты и показать количество рабочих целей.',function()
 scanTrees(true)
 local s=treeScanStats
 local msg='Деревья: всего '..s.all..', рядом '..s.near..', пригодно '..s.valid..
  ', HP0 '..s.hpZero..', без ствола '..s.noVisible..
  ', ближайшее '..(s.closest and math.floor(s.closest+.5) or '?')..' ст.'
 print('[DeepWoods v3.0] '..msg)
 if type(setclipboard)=='function' then pcall(function()setclipboard(msg)end)end
 status(msg)
end)
row(3,'Отчёт / копировать','Сколько RPC, сколько реально начислено древесины и скорость.',function()
 local msg=report()
 print('[DeepWoods v3.0] '..msg)
 if type(setclipboard)=='function' then pcall(function()setclipboard(msg)end)end
 status(msg)
end)
hint(3,'Одновременно рубит ближайшие стволы, а не 30 дальних. Радиус — только область поиска. RPC не гарантирует засчитанный удар за пределами реальной дальности.')

local function stop()
 if not alive then return end
 alive=false
 enabled.farm=false
 for _,c in ipairs(connections) do pcall(function()c:Disconnect()end)end
 restoreSpeed();restoreCollision()
 for p in pairs(esp) do clearEsp(p)end
 pcall(function()effectFolder:Destroy()end)
 pcall(function()screen:Destroy()end)
 for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub26_Unload','DeepWoodsHub27_Unload','DeepWoodsHub28_Unload','DeepWoodsHub29_Unload','DeepWoodsHub30_Unload'}) do
  if ENV[key]==stop then ENV[key]=nil end
 end
end
ENV.DWH_Unload=stop
ENV.DeepWoodsHub_Unload=stop
ENV.DeepWoodsHub26_Unload=stop
ENV.DeepWoodsHub27_Unload=stop
ENV.DeepWoodsHub28_Unload=stop
ENV.DeepWoodsHub29_Unload=stop
ENV.DeepWoodsHub30_Unload=stop
-- Game can respawn TreeTemplate at the same coordinates as a previous stump.
-- Mark the pool dirty when a new model appears; process it on the next farm tick.
if workspace.DescendantAdded then
 subscribe(workspace.DescendantAdded,function(obj)
  if alive and obj:IsA('Model') and obj.Name=='TreeTemplate' then
   knownTrees[obj]=true
   poolDirty=true;nextTreeScan=-10
  end
 end)
end
if workspace.DescendantRemoving then
 subscribe(workspace.DescendantRemoving,function(obj)
  if alive and obj:IsA('Model') and obj.Name=='TreeTemplate' then
   knownTrees[obj]=nil
   poolDirty=true;nextTreeScan=-10
  end
 end)
end
subscribe(RunService.Stepped,function()
 if alive and role=='farmer' and enabled.noclip then pcall(noclip)end
end)
task.spawn(function()
 local espAt=0
 while alive do
  task.wait(.03)
  if not alive then break end
  local now=os.clock()
  local ok,m=pcall(updateMovement)
  if not ok then status('Ошибка движения: '..tostring(m):sub(1,60))end
  if role=='farmer' and enabled.farm then
   local success,err=pcall(doFarm,now)
   if not success then lastFarmMessage='Ошибка AFK: '..tostring(err):sub(1,70)end
  end
  if now>=espAt then
   espAt=now+.70
   pcall(refreshESP)
   if enabled.farm and now-lastUiUpdate>=.75 then
    lastUiUpdate=now
    status(lastFarmMessage..' | +'..(lastWood and totalWood or '?')..' древесины')
   end
  end
 end
end)
print('[DeepWoods v3.0] Priority multi-tree: near targets before distant RPC.')
status('Выбери роль: фермер или убийца')
