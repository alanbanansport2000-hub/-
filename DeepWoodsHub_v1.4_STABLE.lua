-- DeepWoods Hub v1.4 STABLE | Survive Deep in the Woods
-- Fresh mobile UI, static pages, independent controls. No third-party loaders.
-- This script deletes ONLY its own old windows; never Roblox or Delta menus.

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local CollectionService = game:GetService('CollectionService')
local player = Players.LocalPlayer
local playerGui = player:WaitForChild('PlayerGui')
local globals = (getgenv and getgenv()) or _G

for _, name in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload'}) do
    if type(globals[name]) == 'function' then pcall(globals[name]) end
end
-- Clean up only previous versions of this hub (old code may have crashed).
for _, child in ipairs(playerGui:GetChildren()) do
    if child:IsA('BillboardGui') and (child.Name=='DWH_NameAndDistance' or child.Name=='DWH14_PlayerLabel') then
        pcall(function() child:Destroy() end)
    end
end
for _, name in ipairs({'DeepWoodsHub_OwnWindow','DeepWoodsHub_OnlyOwnGui','DeepWoodsHub_v12','DeepWoodsHub_v13_FIX','DeepWoodsHub_v14_STABLE'}) do
    local old = playerGui:FindFirstChild(name)
    if old and old:IsA('ScreenGui') then pcall(function() old:Destroy() end) end
end
for _, name in ipairs({'DeepWoodsHub_Effects','DeepWoodsHub_LocalVisuals','DeepWoodsHub_PlayerEffects','DeepWoodsHub_v13_Visuals','DeepWoodsHub_v14_Effects'}) do
    local old = workspace:FindFirstChild(name)
    if old and old:IsA('Folder') then pcall(function() old:Destroy() end) end
end

local running = true
local listeners = {}
local enabled = {esp=false, distance=true, speed=false, noclip=false, bright=false, chop=false, walk=false}
local walkSpeed = 32
local hpThreshold = 100
local chopRadius = 16
local chopInterval = 0.65
local lastChop = 0
local chopAttempts = 0
local originalSpeed, speedHumanoid = nil, nil
local originalCollision = {}
local previousLighting = {
    Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime,
    FogEnd=Lighting.FogEnd, GlobalShadows=Lighting.GlobalShadows,
    Ambient=Lighting.Ambient
}
local visuals = {}
local cachedTrees = {}
local lastTreeScan = -100
local summary = 'v1.4 запущена. Проверка кнопок: вкладка Настройки.'
local theme = {
    bg=Color3.fromRGB(17,22,32), panel=Color3.fromRGB(26,34,49),
    control=Color3.fromRGB(38,48,65), accent=Color3.fromRGB(66,184,232),
    text=Color3.fromRGB(238,245,250), pale=Color3.fromRGB(175,197,210),
    green=Color3.fromRGB(58,215,148), red=Color3.fromRGB(255,78,100),
    off=Color3.fromRGB(87,94,110)
}

local function connect(signal,fn)
    local c=signal:Connect(fn)
    listeners[#listeners+1]=c
    return c
end
local function create(class,parent,properties)
    local obj=Instance.new(class)
    for key,val in pairs(properties or {}) do obj[key]=val end
    obj.Parent=parent
    return obj
end
local function round(obj,r)
    create('UICorner',obj,{CornerRadius=UDim.new(0,r or 9)})
end
local function character()
    local char=player.Character
    return char, char and char:FindFirstChildOfClass('Humanoid'), char and char:FindFirstChild('HumanoidRootPart')
end
local function viewport()
    local camera=workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(760,390)
end

local gui = create('ScreenGui',playerGui,{
    Name='DeepWoodsHub_v14_STABLE',ResetOnSpawn=false,
    IgnoreGuiInset=true,DisplayOrder=950,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    Enabled=true
})
local effectFolder=create('Folder',workspace,{Name='DeepWoodsHub_v14_Effects'})
local screenSize=viewport()
local panelWidth=math.min(360, math.max(250,screenSize.X-24))
local panelHeight=math.min(365, math.max(235,screenSize.Y-24))
local panel=create('Frame',gui,{
    Name='Window',BackgroundColor3=theme.bg,BorderSizePixel=0,
    Size=UDim2.fromOffset(panelWidth,panelHeight),
    Position=UDim2.fromOffset(math.max(8,math.floor((screenSize.X-panelWidth)/2)),
        math.max(8,math.floor((screenSize.Y-panelHeight)/2))),
    Active=true,Visible=true,ZIndex=2
})
round(panel,14)
create('UIStroke',panel,{Color=theme.accent,Thickness=1.5})
local header=create('Frame',panel,{
    Name='Header',Size=UDim2.new(1,0,0,44),BackgroundColor3=theme.panel,
    BorderSizePixel=0,Active=true,ZIndex=3
})
round(header,12)
local handle=create('TextButton',header,{
    Name='MoveByThis',Text='🌲  DeepWoods Hub  v1.4',Font=Enum.Font.GothamBold,
    TextSize=14,TextColor3=theme.text,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,BorderSizePixel=0,
    Size=UDim2.new(1,-95,1,0),Position=UDim2.fromOffset(10,0),
    AutoButtonColor=false,Active=true,ZIndex=4
})
local function topButton(title,x,color)
    local b=create('TextButton',header,{
        Text=title,Font=Enum.Font.GothamBold,TextSize=20,TextColor3=theme.text,
        BackgroundColor3=color,BorderSizePixel=0,Active=true,AutoButtonColor=true,
        Size=UDim2.fromOffset(30,30),Position=UDim2.new(1,x,0,7),ZIndex=8
    })
    round(b,7)
    return b
end
local minimize=topButton('−',-72,theme.control)
local close=topButton('×',-37,Color3.fromRGB(168,61,74))
local bubble=create('TextButton',gui,{
    Name='FloatingIcon',Text='🌲',Font=Enum.Font.GothamBold,TextSize=27,
    TextColor3=theme.text,BackgroundColor3=theme.panel,
    BorderSizePixel=0,Size=UDim2.fromOffset(53,53),
    Position=UDim2.fromOffset(12,math.floor(screenSize.Y/2)),
    Visible=false,Active=true,ZIndex=15
})
round(bubble,16)
create('UIStroke',bubble,{Color=theme.accent,Thickness=2})

local footer=create('TextLabel',panel,{
    Name='Status',Text=summary,Font=Enum.Font.Gotham,TextSize=10,
    TextColor3=theme.pale,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true,
    BackgroundColor3=theme.panel,BorderSizePixel=0,
    Position=UDim2.new(0,9,1,-39),Size=UDim2.new(1,-18,0,31),ZIndex=3
})
round(footer,7)
local function status(message)
    summary=tostring(message)
    if running and footer.Parent then footer.Text='  '..summary end
end

local function restoreSpeed()
    if speedHumanoid and speedHumanoid.Parent and originalSpeed~=nil then
        pcall(function() speedHumanoid.WalkSpeed=originalSpeed end)
    end
    speedHumanoid,originalSpeed=nil,nil
end
local function restoreLight()
    for property,value in pairs(previousLighting) do
        pcall(function() Lighting[property]=value end)
    end
end
local function restoreCollision()
    for part,wasCollidable in pairs(originalCollision) do
        if part and part.Parent then pcall(function() part.CanCollide=wasCollidable end) end
    end
    originalCollision={}
end
local function clearESP(other)
    local data=visuals[other]
    if not data then return end
    for _,object in ipairs(data.instances) do
        pcall(function() object:Destroy() end)
    end
    visuals[other]=nil
end
local function unload()
    if not running then return end
    running=false
    for _,listener in ipairs(listeners) do pcall(function() listener:Disconnect() end) end
    for p in pairs(visuals) do clearESP(p) end
    restoreSpeed()
    restoreCollision()
    restoreLight()
    pcall(function() effectFolder:Destroy() end)
    pcall(function() gui:Destroy() end)
    for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload'}) do
        if globals[key]==unload then globals[key]=nil end
    end
end
for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload'}) do
    globals[key]=unload
end

-- A single handler per button, with touch fallback and duplicate-event protection.
local function click(button,callback)
    local lastPressed=-100
    local function press()
        if not running or os.clock()-lastPressed<0.18 then return end
        lastPressed=os.clock()
        local ok,err=pcall(callback)
        if not ok then status('Ошибка кнопки: '..tostring(err):sub(1,100)) end
    end
    connect(button.Activated,press)
    connect(button.MouseButton1Click,press)
    connect(button.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.Touch then press() end
    end)
end

-- Roblox-recommended drag approach: track input movement, not just a click.
local bubbleDragHoldoff = 0
local function drag(surf,target,isBubble)
    local dragging=false
    local dragStart, startPos, dragInput = nil,nil,nil
    local moved=false
    connect(surf.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true
            dragStart=input.Position
            startPos=target.Position
            dragInput=input
            moved=false
        end
    end)
    connect(surf.InputChanged,function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
            dragInput=input
        end
    end)
    connect(UserInputService.InputChanged,function(input)
        if not dragging or not dragStart or not startPos then return end
        if input~=dragInput and input.UserInputType~=Enum.UserInputType.Touch then return end
        local delta=input.Position-dragStart
        if delta.Magnitude>7 then
            moved=true
            if isBubble then bubbleDragHoldoff=os.clock()+0.6 end
        end
        local newX=startPos.X.Offset+delta.X
        local newY=startPos.Y.Offset+delta.Y
        local v=viewport()
        newX=math.clamp(newX,0,math.max(0,v.X-target.AbsoluteSize.X))
        newY=math.clamp(newY,0,math.max(0,v.Y-target.AbsoluteSize.Y))
        target.Position=UDim2.fromOffset(newX,newY)
    end)
    connect(UserInputService.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or
           input.UserInputType==Enum.UserInputType.Touch then
            if isBubble and moved then bubbleDragHoldoff=os.clock()+0.6 end
            dragging=false
        end
    end)
end
drag(handle,panel,false)
drag(bubble,bubble,true)

local function shrink()
    bubble.Position=UDim2.fromOffset(panel.AbsolutePosition.X,panel.AbsolutePosition.Y)
    panel.Visible=false
    bubble.Visible=true
end
local function expand()
    local v=viewport()
    panel.Position=UDim2.fromOffset(
        math.clamp(bubble.AbsolutePosition.X,0,math.max(0,v.X-panelWidth)),
        math.clamp(bubble.AbsolutePosition.Y,0,math.max(0,v.Y-panelHeight)))
    bubble.Visible=false
    panel.Visible=true
end
click(minimize,shrink)
click(close,unload)
click(bubble,function()
    if os.clock() < bubbleDragHoldoff then return end
    expand()
end)

-- Static page content: NOTHING is destroyed when tabs are changed.
local nav=create('Frame',panel,{
    Name='Tabs',Position=UDim2.fromOffset(8,49),Size=UDim2.new(1,-16,0,36),
    BackgroundTransparency=1,BorderSizePixel=0,ZIndex=3
})
local pageBox=create('Frame',panel,{
    Name='PageBox',Position=UDim2.fromOffset(8,90),
    Size=UDim2.new(1,-16,1,-133),BackgroundTransparency=1,
    BorderSizePixel=0,ClipsDescendants=true,ZIndex=3
})
local names={'ESP','Движение','Дерево','Настройки'}
local pages={}
local tabs={}
local pageY={}
local tabWidth=math.floor((panelWidth-16-18)/4)
local function makePage(i)
    local page=create('ScrollingFrame',pageBox,{
        Name='Page_'..i,Size=UDim2.fromScale(1,1),Position=UDim2.fromOffset(0,0),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,
        ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,0),
        Visible=i==1,Active=true,ZIndex=4
    })
    pages[i]=page
    pageY[i]=5
    return page
end
for i=1,#names do
    local idx=i
    local tab=create('TextButton',nav,{
        Name='Tab_'..i,Text=names[i],Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=theme.pale,BackgroundColor3=theme.control,
        Position=UDim2.fromOffset((i-1)*(tabWidth+6),0),
        Size=UDim2.fromOffset(tabWidth,34),BorderSizePixel=0,
        AutoButtonColor=true,Active=true,ZIndex=5
    })
    round(tab,7)
    tabs[i]=tab
    makePage(i)
    click(tab,function()
        for n,p in ipairs(pages) do
            p.Visible=(n==idx)
            tabs[n].BackgroundColor=(n==idx) and theme.accent or theme.control
            tabs[n].TextColor3=(n==idx) and theme.bg or theme.pale
        end
        status('Вкладка: '..names[idx]..' • кнопки готовы')
    end)
end
tabs[1].BackgroundColor=theme.accent
tabs[1].TextColor3=theme.bg

local function addLine(pageId,text,isHeading)
    local page=pages[pageId]
    local height=isHeading and 27 or 47
    local textBox=create('TextLabel',page,{
        Text=text,Font=isHeading and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize=isHeading and 13 or 11,TextColor3=isHeading and theme.accent or theme.pale,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        Position=UDim2.fromOffset(7,pageY[pageId]),Size=UDim2.new(1,-15,0,height),
        BackgroundTransparency=isHeading and 1 or 0,
        BackgroundColor3=theme.panel,BorderSizePixel=0,Active=false,ZIndex=5
    })
    if not isHeading then round(textBox,8) end
    pageY[pageId]=pageY[pageId]+height+7
    page.CanvasSize=UDim2.fromOffset(0,pageY[pageId]+8)
    return textBox
end
local function addButton(pageId,title,description,callback,flag)
    local page=pages[pageId]
    local button=create('TextButton',page,{
        Text='',Font=Enum.Font.Gotham,TextSize=12,
        Position=UDim2.fromOffset(4,pageY[pageId]),
        Size=UDim2.new(1,-13,0,61),BackgroundColor3=theme.control,
        BorderSizePixel=0,AutoButtonColor=true,Active=true,ZIndex=5
    })
    round(button,9)
    local titleLabel=create('TextLabel',button,{
        Text=title,Font=Enum.Font.GothamBold,TextSize=12,
        TextColor3=theme.text,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        Position=UDim2.fromOffset(9,6),Size=UDim2.new(1,flag and -78 or -18,0,23),
        BackgroundTransparency=1,Active=false,ZIndex=6
    })
    create('TextLabel',button,{
        Text=description,Font=Enum.Font.Gotham,TextSize=10,
        TextColor3=theme.pale,TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        Position=UDim2.fromOffset(9,30),Size=UDim2.new(1,flag and -78 or -18,0,29),
        BackgroundTransparency=1,Active=false,ZIndex=6
    })
    local chip
    if flag then
        chip=create('TextLabel',button,{
            Text='ВЫКЛ',Font=Enum.Font.GothamBold,TextSize=10,
            TextColor3=theme.text,BackgroundColor3=theme.off,
            Position=UDim2.new(1,-65,0,18),Size=UDim2.fromOffset(56,25),
            TextXAlignment=Enum.TextXAlignment.Center,BorderSizePixel=0,
            Active=false,ZIndex=6
        })
        round(chip,7)
    end
    local function redraw()
        if chip then
            chip.Text=enabled[flag] and 'ВКЛ' or 'ВЫКЛ'
            chip.BackgroundColor3=enabled[flag] and theme.green or theme.off
        end
    end
    click(button,function()
        if flag then enabled[flag]=not enabled[flag] end
        redraw()
        callback(titleLabel)
    end)
    redraw()
    pageY[pageId]=pageY[pageId]+68
    page.CanvasSize=UDim2.fromOffset(0,pageY[pageId]+8)
    return button
end

-- Player ESP, with HP heuristic and live distance.
local function refreshESP()
    if not enabled.esp then
        for other in pairs(visuals) do clearESP(other) end
        return 0
    end
    local _,_,myRoot=character()
    local seen={}
    local count=0
    for _,other in ipairs(Players:GetPlayers()) do
        if other~=player then
            local c=other.Character
            local hum=c and c:FindFirstChildOfClass('Humanoid')
            local head=c and (c:FindFirstChild('Head') or c:FindFirstChild('HumanoidRootPart'))
            if c and hum and head and hum.Health>0 then
                local saved=visuals[other]
                if saved and saved.char~=c then clearESP(other);saved=nil end
                if not saved then
                    local h=create('Highlight',effectFolder,{
                        Adornee=c,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency=0.8,OutlineTransparency=0
                    })
                    local billboard=create('BillboardGui',playerGui,{
                        Name='DWH14_PlayerLabel',Adornee=head,AlwaysOnTop=true,
                        Size=UDim2.fromOffset(185,53),StudsOffset=Vector3.new(0,3,0),
                        MaxDistance=2500,Enabled=true
                    })
                    local label=create('TextLabel',billboard,{
                        Size=UDim2.fromScale(1,1),Font=Enum.Font.GothamBold,
                        TextSize=12,TextWrapped=true,TextStrokeTransparency=0.25,
                        BackgroundColor3=theme.bg,BackgroundTransparency=0.25,
                        TextColor3=theme.green,BorderSizePixel=0
                    })
                    round(label,7)
                    saved={char=c,h=h,bill=billboard,label=label,instances={h,billboard}}
                    visuals[other]=saved
                end
                local suspect=hum.MaxHealth>hpThreshold
                local color=suspect and theme.red or theme.green
                saved.h.FillColor=color
                saved.h.OutlineColor=color
                saved.label.TextColor3=color
                local distance=myRoot and math.floor((head.Position-myRoot.Position).Magnitude+0.5) or nil
                saved.label.Text=other.DisplayName..(suspect and ' • ВОЗМ. УБИЙЦА' or '')..'\n'..
                    'HP '..math.ceil(hum.Health)..'/'..math.ceil(hum.MaxHealth)..
                    (enabled.distance and distance and (' • '..distance..' ст.') or '')
                seen[other]=true
                count=count+1
            end
        end
    end
    for other in pairs(visuals) do
        if not seen[other] then clearESP(other) end
    end
    return count
end

-- Wood-cutting remains experimental until actual tree/axe mechanics are observed.
local function positionOf(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA('BasePart') then return obj.Position end
    if obj:IsA('Model') then
        local p=obj:FindFirstChildWhichIsA('BasePart',true)
        return p and p.Position
    end
    return nil
end
local function isTree(obj)
    local n=string.lower(obj.Name)
    for _,word in ipairs({'tree','trunk','oak','pine','birch','spruce','дерево','ствол'}) do
        if string.find(n,word,1,true) then return true end
    end
    return false
end
local function scanTrees(force)
    if not force and os.clock()-lastTreeScan<5 then return end
    lastTreeScan=os.clock()
    local found,marked={},{}
    local function add(obj)
        if #found>=500 or not obj or not obj.Parent then return end
        if obj:IsA('BasePart') and obj.Parent and obj.Parent:IsA('Model') and isTree(obj.Parent) then obj=obj.Parent end
        if not marked[obj] and (obj:IsA('Model') or obj:IsA('BasePart')) and positionOf(obj) then
            marked[obj]=true
            found[#found+1]=obj
        end
    end
    for _,tag in ipairs({'Tree','ChoppableTree','HarvestableTree'}) do
        local ok,things=pcall(function() return CollectionService:GetTagged(tag) end)
        if ok then for _,obj in ipairs(things) do add(obj) end end
    end
    for _,obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA('Model') or obj:IsA('BasePart')) and isTree(obj) then add(obj) end
        if #found>=500 then break end
    end
    cachedTrees=found
end
local function closestTree(maxDistance)
    local _,_,myRoot=character()
    if not myRoot then return nil,nil end
    scanTrees(false)
    local closest,shortest=nil,maxDistance
    for _,obj in ipairs(cachedTrees) do
        local pos=positionOf(obj)
        if pos then
            local dx=pos.X-myRoot.Position.X
            local dz=pos.Z-myRoot.Position.Z
            local distance=math.sqrt(dx*dx+dz*dz)
            if distance<shortest then closest,shortest=obj,distance end
        end
    end
    return closest,shortest
end
local function equippedAxe()
    local char,hum=character()
    if not char or not hum then return nil end
    local function matches(tool)
        if not tool:IsA('Tool') then return false end
        local name=string.lower(tool.Name..' '..tool.ToolTip)
        return name:find('axe',1,true) or name:find('hatchet',1,true) or name:find('chop',1,true) or name:find('топор',1,true)
    end
    for _,item in ipairs(char:GetChildren()) do if matches(item) then return item end end
    local backpack=player:FindFirstChild('Backpack')
    if backpack then
        for _,item in ipairs(backpack:GetChildren()) do
            if matches(item) then
                pcall(function() hum:EquipTool(item) end)
                return item
            end
        end
    end
    return nil
end
local function chopTick()
    if os.clock()-lastChop<chopInterval then return end
    lastChop=os.clock()
    local _,hum,myRoot=character()
    if not hum or not myRoot or hum.Health<=0 then return end
    local tool=equippedAxe()
    if not tool then status('Рубка: не найден топор Tool') return end
    local target,distance=closestTree(enabled.walk and 175 or chopRadius)
    if not target then status('Рубка: дерево не найдено (распознано '..#cachedTrees..')') return end
    if distance>chopRadius then
        if enabled.walk then
            local p=positionOf(target)
            if p then pcall(function() hum:MoveTo(p) end) end
            status('Рубка: иду к дереву '..math.floor(distance)..' ст.')
        end
        return
    end
    local ok=pcall(function() tool:Activate() end)
    if ok then chopAttempts=chopAttempts+1 end
    status('Рубка: попыток '..chopAttempts..' | добыча не подтверждена')
end
local function noclipTick()
    local char=player.Character
    if not char then return end
    for _,part in ipairs(char:GetDescendants()) do
        if part:IsA('BasePart') and part.CanCollide then
            if originalCollision[part]==nil then originalCollision[part]=part.CanCollide end
            part.CanCollide=false
        end
    end
end

-- Controls: created once, not re-rendered after a click.
addLine(1,'ИГРОКИ',true)
addButton(1,'ESP игроков','Подсветка через стены, имя, HP и дистанция.',function()
    if not enabled.esp then for p in pairs(visuals) do clearESP(p) end end
    status(enabled.esp and 'ESP включён' or 'ESP выключен')
end,'esp')
addButton(1,'Расстояние','Число студий до каждого видимого в ESP игрока.',function()
    status(enabled.distance and 'Расстояние включено' or 'Расстояние выключено')
end,'distance')
addButton(1,'Порог HP: > 100','Меняет порог выделения красным: 100 / 120 / 150 / 200.',function(title)
    local values={100,120,150,200}
    local index=table.find(values,hpThreshold) or 1
    hpThreshold=values[index%#values+1]
    title.Text='Порог HP: > '..hpThreshold
    status('Красный — MaxHealth выше '..hpThreshold)
end)
addLine(1,'Красный = предполагаемый убийца по MaxHealth. Это не подтверждённая роль.',false)

addLine(2,'ПЕРЕДВИЖЕНИЕ',true)
addButton(2,'Ускоренный бег','Поддерживает выбранную скорость каждые 0,2 с.',function()
    if not enabled.speed then restoreSpeed() end
    status(enabled.speed and 'Ускорение включено' or 'Ускорение выключено')
end,'speed')
addButton(2,'Скорость: 32','Переключает 24 / 32 / 40 / 60 / 90.',function(title)
    local values={24,32,40,60,90}
    local index=table.find(values,walkSpeed) or 1
    walkSpeed=values[index%#values+1]
    title.Text='Скорость: '..walkSpeed
    status('Установлена скорость '..walkSpeed)
end)
addButton(2,'Noclip','Временно выключает столкновение с частями персонажа.',function()
    if not enabled.noclip then restoreCollision() end
    status(enabled.noclip and 'Noclip включён' or 'Noclip выключен')
end,'noclip')
addLine(2,'Некоторые серверы могут ограничивать движение. Выключение восстанавливает настройки.',false)

addLine(3,'ДЕРЕВО · ТЕСТ',true)
addButton(3,'Авторубка дерева','Пробует активировать топор рядом с деревом.',function()
    status(enabled.chop and 'Тестовая авторубка включена' or 'Авторубка выключена')
end,'chop')
addButton(3,'Подход к дереву','Автоматически идёт к ближайшему дереву без телепорта.',function()
    status(enabled.walk and 'Подход включён' or 'Подход выключен')
end,'walk')
addButton(3,'Радиус: 16','Выбор радиуса: 10 / 16 / 22 студии.',function(title)
    chopRadius=(chopRadius==10 and 16 or chopRadius==16 and 22 or 10)
    title.Text='Радиус: '..chopRadius
    status('Дальность: '..chopRadius..' студ.')
end)
addButton(3,'Проверить инструмент','Покажет число найденных деревьев и название топора.',function()
    scanTrees(true)
    local tool=equippedAxe()
    local _,distance=closestTree(200)
    status('Деревьев: '..#cachedTrees..' | Топор: '..(tool and tool.Name or 'нет')..' | Ближайшее: '..(distance and math.floor(distance)..' ст.' or 'нет'))
end)
addLine(3,'Рубка экспериментальная: сервер может не начислять дерево от Tool:Activate().',false)

addLine(4,'НАСТРОЙКИ',true)
addButton(4,'Fullbright','Увеличивает освещение, убирает сильную темноту.',function()
    if not enabled.bright then restoreLight() end
    status(enabled.bright and 'Fullbright включён' or 'Fullbright выключен')
end,'bright')
addButton(4,'ТЕСТ КНОПОК','Нажми: строка снизу изменится на «Нажатие работает».',function()
    status('✅ Нажатие работает, версия 1.4')
end)
addButton(4,'Свернуть в иконку','Оставляет небольшую кнопку 🌲.',function() shrink() end)
addButton(4,'Закрыть скрипт','Удаляет только это окно и его ESP; возвращает настройки.',function() unload() end)
addLine(4,'Перетаскивай окно за верхний заголовок. Вкладки больше не пересоздаются.',false)

connect(RunService.Stepped,function()
    if running and enabled.noclip then pcall(noclipTick) end
end)

task.spawn(function()
    local nextESP=0
    while running do
        task.wait(0.2)
        if not running then break end
        local _,hum=character()
        if enabled.speed and hum then
            if hum~=speedHumanoid then
                restoreSpeed()
                speedHumanoid=hum
                originalSpeed=hum.WalkSpeed
            end
            pcall(function() hum.WalkSpeed=walkSpeed end)
        elseif speedHumanoid then
            restoreSpeed()
        end
        if enabled.bright then
            pcall(function()
                Lighting.Brightness=3
                Lighting.ClockTime=14
                Lighting.FogEnd=100000
                Lighting.GlobalShadows=false
                Lighting.Ambient=Color3.fromRGB(200,200,200)
            end)
        end
        if enabled.chop then
            local ok,err=pcall(chopTick)
            if not ok then status('Ошибка дерева: '..tostring(err):sub(1,95)) end
        end
        if os.clock()>nextESP then
            nextESP=os.clock()+0.45
            local ok,value=pcall(refreshESP)
            if not ok then status('Ошибка ESP: '..tostring(value):sub(1,95)) end
        end
    end
end)
status('v1.4 STABLE • кнопки созданы, вкладки заполнены')
