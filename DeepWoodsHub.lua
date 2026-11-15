-- DeepWoods Hub v1.0 | Survive Deep in the Woods
-- Self contained: no key system, remote loader or destructive GUI sweeps.
local Players=game:GetService('Players')
local RS=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local Lighting=game:GetService('Lighting')
local LP=Players.LocalPlayer
local ENV=(getgenv and getgenv()) or _G
if type(ENV.DWH_Unload)=='function' then pcall(ENV.DWH_Unload) end
local alive=true
local conns={}
local flags={players=false,trees=false,bright=false,speed=false,noclip=false,jump=false,chop=false,collect=false,build=false,farms=false,teleport=false}
local walk=32
local oldWalk=nil
local savedCollisions={}
local oldLight={Brightness=Lighting.Brightness,ClockTime=Lighting.ClockTime,FogEnd=Lighting.FogEnd,GlobalShadows=Lighting.GlobalShadows}
local esp={}
local statusText='Готово. Рубка и строительство экспериментальные.'
local farmTypes={'Chicken','Cow','Pig','Sheep'}
local farmIndex=1
local root=Instance.new('Folder');root.Name='DeepWoodsHub_Effects';root.Parent=workspace
local function connect(sig,fun) local c=sig:Connect(fun);conns[#conns+1]=c;return c end
local function character() local ch=LP.Character;return ch,ch and ch:FindFirstChildOfClass('Humanoid'),ch and ch:FindFirstChild('HumanoidRootPart') end
local function pos(obj)
 if not obj or not obj.Parent then return nil end
 if obj:IsA('BasePart') then return obj.Position end
 if obj:IsA('Model') then local ok,p=pcall(function()return obj:GetPivot().Position end);if ok then return p end end
 local p=obj:FindFirstChildWhichIsA('BasePart',true);return p and p.Position
end
local function treeName(n) n=n:lower();return n:find('tree',1,true) or n:find('trunk',1,true) or n:find('pine',1,true) or n:find('oak',1,true) or n:find('birch',1,true) end
local treeCache={};local lastScan=0
local function scan()
 if os.clock()-lastScan<6 then return end;lastScan=os.clock()
 treeCache={};local seen={}
 for _,obj in ipairs(workspace:GetDescendants()) do
  if #treeCache>=400 then break end
  if (obj:IsA('BasePart') or obj:IsA('Model')) and treeName(obj.Name) then
   local t=obj
   if obj:IsA('BasePart') and obj.Parent:IsA('Model') and treeName(obj.Parent.Name) then t=obj.Parent end
   if not seen[t] and pos(t) then seen[t]=true;treeCache[#treeCache+1]=t end
  end
 end
end
local function nearTree(range)
 local _,_,hrp=character();if not hrp then return nil end
 scan();local best,d=nil,range or 100
 for _,obj in ipairs(treeCache) do local p=pos(obj);if p then local dist=(p-hrp.Position).Magnitude;if dist<d then best,d=obj,dist end end end
 return best,d
end
local function highlight(id,obj,color,name)
 if esp[id] or not obj or not obj.Parent then return end
 local parts={};local ok=pcall(function()
  local h=Instance.new('Highlight');h.Adornee=obj;h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.FillColor=color;h.OutlineColor=color;h.FillTransparency=.83;h.Parent=root;parts[#parts+1]=h
  local anchor=obj:IsA('BasePart') and obj or obj:FindFirstChild('Head',true) or obj:FindFirstChildWhichIsA('BasePart',true)
  if anchor and name then
   local bill=Instance.new('BillboardGui');bill.Adornee=anchor;bill.Size=UDim2.fromOffset(160,28);bill.StudsOffset=Vector3.new(0,3,0);bill.AlwaysOnTop=true;bill.Parent=root;parts[#parts+1]=bill
   local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text=name;label.Font=Enum.Font.GothamBold;label.TextScaled=true;label.TextStrokeTransparency=.35;label.TextColor3=color;label.Parent=bill
  end
 end)
 if ok then esp[id]=parts end
end
local function refreshESP()
 local valid={}
 if flags.players then for _,p in ipairs(Players:GetPlayers()) do if p~=LP and p.Character and p.Character.Parent then
  local id='P'..p.UserId;valid[id]=true;highlight(id,p.Character,Color3.fromRGB(255,90,100),p.DisplayName)
 end end end
 if flags.trees then
  scan();local _,_,hrp=character();local count=0
  if hrp then for _,obj in ipairs(treeCache) do
   if count>=45 then break end
   local p=pos(obj);if p and (p-hrp.Position).Magnitude<180 then local id='T'..tostring(obj);valid[id]=true;highlight(id,obj,Color3.fromRGB(80,230,120));count=count+1 end
  end end
 end
 for id,parts in pairs(esp) do if not valid[id] then for _,p in ipairs(parts) do pcall(function()p:Destroy()end) end;esp[id]=nil end end
end
local function interact(radius,words,limit)
 local _,_,hrp=character();if not hrp then return 0 end
 local triggered=0
 for _,o in ipairs(workspace:GetDescendants()) do
  if triggered>=(limit or 5) then break end
  if o:IsA('ProximityPrompt') or o:IsA('ClickDetector') then
   local p=pos(o.Parent)
   if p and (p-hrp.Position).Magnitude<radius then
    local s=(o.Name..' '..o.Parent.Name..' '..(o:IsA('ProximityPrompt') and (o.ActionText..' '..o.ObjectText) or '')):lower()
    local match=false;for _,word in ipairs(words) do if s:find(word,1,true) then match=true;break end end
    if match then
     if o:IsA('ProximityPrompt') and type(fireproximityprompt)=='function' then if pcall(fireproximityprompt,o) then triggered=triggered+1 end
     elseif o:IsA('ClickDetector') and type(fireclickdetector)=='function' then if pcall(fireclickdetector,o) then triggered=triggered+1 end end
    end
   end
  end
 end
 return triggered
end
local function axe()
 local ch,hum=character();if not ch or not hum then return nil end
 for _,t in ipairs(ch:GetChildren()) do if t:IsA('Tool') and (t.Name:lower():find('axe') or t.Name:lower():find('hatchet')) then return t end end
 for _,t in ipairs(LP.Backpack:GetChildren()) do if t:IsA('Tool') and (t.Name:lower():find('axe') or t.Name:lower():find('hatchet')) then pcall(function()hum:EquipTool(t)end);return t end end
 return ch:FindFirstChildOfClass('Tool')
end
local function chooseFarm()
 local name=farmTypes[farmIndex]:lower()
 local pg=LP:FindFirstChild('PlayerGui');if not pg then return false end
 for _,o in ipairs(pg:GetDescendants()) do
  if o:IsA('GuiButton') and o.Visible then
   local s=(o.Name..' '..(o:IsA('TextButton') and o.Text or '')..' '..o.Parent.Name):lower()
   if s:find(name,1,true) and (s:find('farm',1,true) or s:find('ферм',1,true)) then return pcall(function()o:Activate()end) end
  end
 end
 return false
end
local gui=Instance.new('ScreenGui');gui.Name='DeepWoodsHub_OwnWindow';gui.ResetOnSpawn=false;gui.DisplayOrder=700;gui.Parent=LP:WaitForChild('PlayerGui')
local function make(kind,parent,props)
 local o=Instance.new(kind);for k,v in pairs(props) do o[k]=v end;o.Parent=parent;return o
end
local function rounded(obj,r) make('UICorner',obj,{CornerRadius=UDim.new(0,r or 8)}) end
local panel=make('Frame',gui,{BackgroundColor3=Color3.fromRGB(18,23,34),BorderSizePixel=0,Size=UDim2.fromOffset(320,440),Position=UDim2.new(.5,-160,.17,0),Active=true});rounded(panel,12)
make('UIStroke',panel,{Thickness=1.4,Color=Color3.fromRGB(69,116,161)})
local bar=make('Frame',panel,{Size=UDim2.new(1,0,0,45),BackgroundColor3=Color3.fromRGB(35,46,67),BorderSizePixel=0,Active=true});rounded(bar,12)
make('TextLabel',bar,{Text='🌲 DeepWoods Hub v1.0',Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.new(1,1,1),TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-85,1,0),BackgroundTransparency=1})
local close=make('TextButton',bar,{Text='×',TextSize=23,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(163,61,70),Size=UDim2.fromOffset(30,28),Position=UDim2.new(1,-37,0,9)});rounded(close)
local mini=make('TextButton',bar,{Text='—',TextSize=19,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(70,85,109),Size=UDim2.fromOffset(30,28),Position=UDim2.new(1,-74,0,9)});rounded(mini)
local scroll=make('ScrollingFrame',panel,{Position=UDim2.fromOffset(8,49),Size=UDim2.new(1,-16,1,-105),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0)})
local layout=make('UIListLayout',scroll,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})
connect(layout:GetPropertyChangedSignal('AbsoluteContentSize'),function()scroll.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+8)end)
local status=make('TextLabel',panel,{Text=statusText,TextWrapped=true,TextSize=11,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(160,203,230),BackgroundColor3=Color3.fromRGB(29,38,51),Position=UDim2.new(0,9,1,-50),Size=UDim2.new(1,-18,0,43)});rounded(status)
local function setStatus(s)statusText=s;status.Text=s end
local function title(s)make('TextLabel',scroll,{Text=s,TextSize=13,Font=Enum.Font.GothamBold,TextColor3=Color3.fromRGB(109,199,250),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,Size=UDim2.new(1,-6,0,24)})end
local function button(label,callback)
 local b=make('TextButton',scroll,{Text=label,Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=Color3.fromRGB(243,248,255),BackgroundColor3=Color3.fromRGB(45,77,108),Size=UDim2.new(1,-8,0,38),BorderSizePixel=0});rounded(b)
 connect(b.Activated,function()if alive then callback(b)end end);return b
end
local function toggle(label,key,onchange)
 local b=button(label..' [ВЫКЛ]',function(b)
  flags[key]=not flags[key];b.Text=label..(flags[key] and ' [ВКЛ]' or ' [ВЫКЛ]')
  if onchange then onchange(flags[key]) end
 end)
 return b
end
title('ESP / ВИДИМОСТЬ')
toggle('ESP игроков + имена','players')
toggle('ESP деревьев','trees')
toggle('Fullbright','bright',function(v)if not v then for k,value in pairs(oldLight) do Lighting[k]=value end end end)
title('ДВИЖЕНИЕ')
toggle('Ускоренный бег','speed')
button('Скорость: 32 → изменить',function(b)
 local choices={24,32,40,60,90};local i=table.find(choices,walk) or 1;walk=choices[i%#choices+1];b.Text='Скорость: '..walk..' → изменить'
end)
toggle('Noclip (сквозь стены)','noclip',function(v)if not v then for p,original in pairs(savedCollisions) do if p.Parent then p.CanCollide=original end end;table.clear(savedCollisions)end end)
toggle('Бесконечные прыжки','jump')
title('АВТОМАТИЗАЦИЯ (ЭКСПЕРИМЕНТАЛЬНО)')
toggle('Авторубка деревьев рядом','chop')
toggle('Автосбор ресурсов рядом','collect')
toggle('Автодостройка рядом','build')
toggle('Автоферма: кнопка строительства','farms')
button('Ферма: Chicken → изменить',function(b)farmIndex=farmIndex%#farmTypes+1;b.Text='Ферма: '..farmTypes[farmIndex]..' → изменить'end)
toggle('Телепорт к ближайшим деревьям','teleport')
button('Пересканировать деревья',function()lastScan=0;scan();setStatus('Распознано объектов: '..#treeCache)end)
local hidden=false
connect(mini.Activated,function()hidden=not hidden;scroll.Visible=not hidden;status.Visible=not hidden;panel.Size=hidden and UDim2.fromOffset(320,45) or UDim2.fromOffset(320,440)end)
local dragging=false;local dragInput=nil;local dragStart=nil;local startPos=nil
connect(bar.InputBegan,function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  dragging=true;dragInput=input;dragStart=input.Position;startPos=panel.Position
 end
end)
connect(UIS.InputChanged,function(input)
 if dragging and dragStart and (input==dragInput or input.UserInputType==Enum.UserInputType.MouseMovement) then
  local d=input.Position-dragStart;panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
 end
end)
connect(UIS.InputEnded,function(input)if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
connect(UIS.JumpRequest,function()if alive and flags.jump then local _,h=character();if h then h:ChangeState(Enum.HumanoidStateType.Jumping)end end end)
connect(RS.Stepped,function()
 if alive and flags.noclip then local ch=LP.Character;if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA('BasePart') and p.CanCollide then if savedCollisions[p]==nil then savedCollisions[p]=true end;p.CanCollide=false end end end end
end)
local function unload()
 if not alive then return end;alive=false
 for _,c in ipairs(conns) do pcall(function()c:Disconnect()end)end
 for p,original in pairs(savedCollisions) do if p.Parent then pcall(function()p.CanCollide=original end)end end
 for k,v in pairs(oldLight) do pcall(function()Lighting[k]=v end)end
 local _,h=character();if h and oldWalk then pcall(function()h.WalkSpeed=oldWalk end)end
 pcall(function()root:Destroy()end);pcall(function()gui:Destroy()end)
 if ENV.DWH_Unload==unload then ENV.DWH_Unload=nil end
end
ENV.DWH_Unload=unload
connect(close.Activated,unload)
task.spawn(function()
 local nextESP=0;local lastAction=0;local lastFarm=0;local lastTP=0
 while alive do
  task.wait(.25);if not alive then break end
  local _,h,hrp=character()
  if h then
   if flags.speed then if oldWalk==nil then oldWalk=h.WalkSpeed end;pcall(function()h.WalkSpeed=walk end)
   elseif oldWalk then pcall(function()h.WalkSpeed=oldWalk end);oldWalk=nil end
  end
  if flags.bright then Lighting.Brightness=3;Lighting.ClockTime=14;Lighting.FogEnd=100000;Lighting.GlobalShadows=false end
  if os.clock()>=nextESP then nextESP=os.clock()+2.5;pcall(refreshESP)end
  if os.clock()-lastAction>=.8 then
   lastAction=os.clock()
   if flags.chop then
    local obj=nearTree(22)
    if obj then
     local tool=axe();if tool then pcall(function()tool:Activate()end)end
     local n=interact(22,{'chop','cut','tree','wood'},3)
     setStatus('Рубка: инструмент '..(tool and 'найден' or 'не найден')..', взаимодействий '..n..'. Проверь древесину.')
    else setStatus('Рубка: рядом нет распознанных деревьев')end
   end
   if flags.collect then local n=interact(18,{'collect','pickup','take','loot','wood'},6);if n>0 then setStatus('Автосбор: '..n..' взаимодействий')end end
   if flags.build then local n=interact(18,{'build','construct','upgrade','finish'},5);if n>0 then setStatus('Постройка: '..n..' взаимодействий, результат проверь')end end
  end
  if flags.farms and os.clock()-lastFarm>=5 then
   lastFarm=os.clock();local ok=chooseFarm()
   setStatus(ok and ('Ферма '..farmTypes[farmIndex]..': кнопка выбрана; размести вручную') or 'Ферма: не найдена подходящая кнопка в меню строительства')
  end
  if flags.teleport and os.clock()-lastTP>=4 then
   lastTP=os.clock();local obj,d=nearTree(150)
   if obj and hrp and d and d>12 then local p=pos(obj);if p then pcall(function()hrp.CFrame=CFrame.new(p+Vector3.new(0,5,8))end)end end
  end
 end
end)
setStatus('Готово. Закрытие × удаляет только этот скрипт и его эффекты.')
