-- DeepWoods Hub v1.8 TARGET+WOOD | Survive Deep in the Woods
-- Fresh mobile UI, static pages, independent controls. No third-party loaders.
-- This script deletes ONLY its own old windows; never Roblox or Delta menus.

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local CollectionService = game:GetService('CollectionService')
local ContextActionService = game:GetService('ContextActionService')
local player = Players.LocalPlayer
local playerGui = player:WaitForChild('PlayerGui')
local globals = (getgenv and getgenv()) or _G

for _, name in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload','DeepWoodsHub15_Unload','DeepWoodsHub16_Unload','DeepWoodsHub17_Unload','DeepWoodsHub18_Unload'}) do
    if type(globals[name]) == 'function' then pcall(globals[name]) end
end
-- Clean up only previous versions of this hub (old code may have crashed).
for _, child in ipairs(playerGui:GetChildren()) do
    if child:IsA('BillboardGui') and (child.Name=='DWH_NameAndDistance' or child.Name=='DWH14_PlayerLabel') then
        pcall(function() child:Destroy() end)
    end
end
for _, name in ipairs({'DeepWoodsHub_OwnWindow','DeepWoodsHub_OnlyOwnGui','DeepWoodsHub_v12','DeepWoodsHub_v13_FIX','DeepWoodsHub_v14_STABLE','DeepWoodsHub_v15_FIX','DeepWoodsHub_v16_FIX','DeepWoodsHub_v17_WOOD','DeepWoodsHub_v18_TARGET'}) do
    local old = playerGui:FindFirstChild(name)
    if old and old:IsA('ScreenGui') then pcall(function() old:Destroy() end) end
end
for _, name in ipairs({'DeepWoodsHub_Effects','DeepWoodsHub_LocalVisuals','DeepWoodsHub_PlayerEffects','DeepWoodsHub_v13_Visuals','DeepWoodsHub_v14_Effects','DeepWoodsHub_v15_Effects','DeepWoodsHub_v16_Effects','DeepWoodsHub_v17_Effects','DeepWoodsHub_v18_Effects'}) do
    local old = workspace:FindFirstChild(name)
    if old and old:IsA('Folder') then pcall(function() old:Destroy() end) end
end

local running = true
local listeners = {}
local enabled = {esp=false, distance=true, speed=false, noclip=false, bright=false, chop=false, walk=true, aim=true}
local walkSpeed = 32
local hpThreshold = 100
local chopRadius = 6
local chopInterval = 0.65
local lastChop = 0
local chopAttempts = 0
local swingCache, swingScanAt = nil, -100
local swingName = 'не найдена'
local calibrationPos = nil
local calibrating = false
local swingMethod = 'signal' -- auto / virtual / signal / tool
local swingModes = {'auto','virtual','signal','tool'}
local swingModeLabels = {'Авто','Тап','Сигнал','Tool'}
local swingModeIndex = 3
local espRanges = {180,350,650,1200}
local espRangeIndex = 2
local originalSpeed, speedHumanoid = nil, nil
local originalCollision = {}
local previousLighting = {
    Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime,
    FogEnd=Lighting.FogEnd, GlobalShadows=Lighting.GlobalShadows,
    Ambient=Lighting.Ambient
}
local visuals = {}
local cachedTrees = {}
-- A real tree target is kept between swings; camera and character face it.
local woodTarget = nil
local woodTargetSince = 0
local woodHitsAtTarget = 0
local woodLastMove = 0
local woodLastPosition = nil
local woodBlockedUntil = setmetatable({}, {__mode='k'})
local woodHighlight = nil
local restoreCameraState = nil
local restoreRotateState = nil
local stopWoodAim = function() end
local lastTreeScan = -100
local summary = 'v1.8: ближайшее дерево + автонаведение + Swing.'
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
    for key,val in pairs(properties or {}) do
        assert(type(key)=='string', 'Invalid GUI property key: '..tostring(key))
        obj[key]=val
    end
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
    Name='DeepWoodsHub_v18_TARGET',ResetOnSpawn=false,
    IgnoreGuiInset=true,DisplayOrder=950,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    Enabled=true
})
local effectFolder=create('Folder',workspace,{Name='DeepWoodsHub_v18_Effects'})
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
    Name='MoveByThis',Text='🌲  DeepWoods Hub  v1.8',Font=Enum.Font.GothamBold,
    TextSize=14,TextColor3=theme.text,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,BorderSizePixel=0,
    Size=UDim2.new(1,-58,1,0),Position=UDim2.fromOffset(10,0),
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
local minimize=topButton('−',-37,theme.control)
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
    stopWoodAim()
    pcall(function() effectFolder:Destroy() end)
    pcall(function() gui:Destroy() end)
    for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload','DeepWoodsHub15_Unload','DeepWoodsHub16_Unload','DeepWoodsHub17_Unload','DeepWoodsHub18_Unload'}) do
        if globals[key]==unload then globals[key]=nil end
    end
end
for _,key in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DeepWoodsHub14_Unload','DeepWoodsHub15_Unload','DeepWoodsHub16_Unload','DeepWoodsHub17_Unload','DeepWoodsHub18_Unload'}) do
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
end

-- Mobile drag: preserve the originating touch InputObject; do not overwrite it
-- with a different touch/mouse movement. Support both surface and UIS signals.
local bubbleDragHoldoff = 0
local bubbleEverMoved = false
local function drag(surf, target, isBubble)
    surf.Active = true
    local activeInput = nil
    local initialPosition = nil
    local initialPoint = nil
    local lastPoint = nil
    local moved = false

    local function move(input)
        if not activeInput or not initialPoint or not initialPosition then return end
        local originIsTouch = activeInput.UserInputType == Enum.UserInputType.Touch
        if originIsTouch then
            if input ~= activeInput then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= activeInput then
            return
        end
        local delta = input.Position - initialPoint
        if delta.Magnitude > 6 then
            moved = true
            if isBubble then bubbleDragHoldoff = os.clock() + 0.4; bubbleEverMoved=true end
        end
        if not moved then return end
        local v = viewport()
        local nx = math.clamp(initialPosition.X.Offset + delta.X, 12, math.max(12, v.X - target.AbsoluteSize.X - 12))
        local ny = math.clamp(initialPosition.Y.Offset + delta.Y, 18, math.max(18, v.Y - target.AbsoluteSize.Y - 18))
        target.Position = UDim2.fromOffset(nx, ny)
        lastPoint = input.Position
    end
    connect(surf.InputBegan,function(input)
        if activeInput then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeInput = input
            initialPoint = input.Position
            initialPosition = target.Position
            lastPoint = initialPoint
            moved = false
        end
    end)
    -- On Android the touch may be delivered on either of these signals.
    connect(surf.InputChanged,move)
    connect(UserInputService.InputChanged,move)
    local function finish(input)
        if not activeInput then return end
        if input == activeInput or (activeInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1) then
            if isBubble and moved then bubbleDragHoldoff = os.clock() + 0.45 end
            activeInput = nil
            initialPoint = nil
            initialPosition = nil
        end
    end
    connect(surf.InputEnded,finish)
    connect(UserInputService.InputEnded,finish)
end
drag(handle,panel,false)
drag(bubble,bubble,true)

local function bubbleSafePosition()
    local v=viewport()
    local w,h=53,53
    local left=math.max(14,math.min(v.X-14-w,18))
    local middle=math.floor((v.Y-h)/2)
    local x,y=left,middle
    if bubbleEverMoved then
        x,y=bubble.Position.X.Offset,bubble.Position.Y.Offset
    end
    return UDim2.fromOffset(math.clamp(x,12,math.max(12,v.X-w-12)),
        math.clamp(y,18,math.max(18,v.Y-h-18)))
end
local function shrink()
    bubble.Position=bubbleSafePosition()
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
            tabs[n].BackgroundColor3=(n==idx) and theme.accent or theme.control
            tabs[n].TextColor3=(n==idx) and theme.bg or theme.pale
        end
        status('Вкладка: '..names[idx]..' • кнопки готовы')
    end)
end
tabs[1].BackgroundColor3=theme.accent
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
                local diff=myRoot and (head.Position-myRoot.Position).Magnitude or 0
                if diff<=espRanges[espRangeIndex] then
                local saved=visuals[other]
                if saved and saved.char~=c then clearESP(other);saved=nil end
                if not saved then
                    local h=create('Highlight',effectFolder,{
                        Adornee=c,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency=0.93,OutlineTransparency=0.16
                    })
                    local billboard=create('BillboardGui',playerGui,{
                        Name='DWH14_PlayerLabel',Adornee=head,AlwaysOnTop=true,
                        Size=UDim2.fromOffset(132,36),StudsOffset=Vector3.new(0,2.6,0),
                        MaxDistance=espRanges[espRangeIndex],Enabled=true
                    })
                    local label=create('TextLabel',billboard,{
                        Size=UDim2.fromScale(1,1),Font=Enum.Font.GothamBold,
                        TextSize=10,TextWrapped=true,TextStrokeTransparency=0.38,
                        BackgroundColor3=theme.bg,BackgroundTransparency=0.48,
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
                saved.bill.MaxDistance=espRanges[espRangeIndex]
                local name=other.DisplayName
                if #name>15 then name=name:sub(1,14)..'…' end
                saved.label.Text=(suspect and '⚠ ' or '')..name..'\n'..
                    math.ceil(hum.Health)..'/'..math.ceil(hum.MaxHealth)..' HP'..
                    (enabled.distance and distance and (' · '..distance..' ст.') or '')
                seen[other]=true
                count=count+1
                end -- distance range
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
        if obj.PrimaryPart then return obj.PrimaryPart.Position end
        local best, bestScore = nil, -100000
        for _,p in ipairs(obj:GetDescendants()) do
            if p:IsA('BasePart') then
                local n=string.lower(p.Name)
                local score=0
                if n:find('trunk',1,true) or n:find('stem',1,true)
                    or n:find('stump',1,true) or n:find('log',1,true)
                    or n:find('ствол',1,true) then score=50 end
                if n:find('leaf',1,true) or n:find('leaves',1,true)
                    or n:find('branch',1,true) then score=score-25 end
                score=score + math.min(p.Size.Y, 15)*.1
                if score>bestScore then best,bestScore=p,score end
            end
        end
        return best and best.Position
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
        if pos and (woodBlockedUntil[obj] or 0)<os.clock() then
            local dx=pos.X-myRoot.Position.X
            local dz=pos.Z-myRoot.Position.Z
            local distance=math.sqrt(dx*dx+dz*dz)
            if distance<shortest then closest,shortest=obj,distance end
        end
    end
    return closest,shortest
end
-- The game displays a "Swing" / "Качели" mobile action button. Its axe
-- is often managed by game UI, NOT a Roblox Tool; avoid Tool-only dependence.
local function equippedAxe()
    local char,hum=character()
    if not char or not hum then return nil end
    local function matches(t)
        if not t:IsA('Tool') then return false end
        local n=string.lower(t.Name..' '..(t.ToolTip or ''))
        return n:find('axe',1,true) or n:find('hatchet',1,true) or
            n:find('топор',1,true)
    end
    for _,t in ipairs(char:GetChildren()) do if matches(t) then return t end end
    local bag=player:FindFirstChild('Backpack')
    if bag then for _,t in ipairs(bag:GetChildren()) do
        if matches(t) then pcall(function() hum:EquipTool(t) end);return t end
    end end
    return nil
end

local function swingMatch(raw)
    local s=string.lower(tostring(raw or ''))
    return s:find('swing',1,true) or s:find('качел',1,true) or s:find('Качел',1,true) or
           s:find('chop',1,true) or s:find('руб',1,true) or s:find('Руб',1,true) or
           s:find('axe',1,true) or s:find('топор',1,true) or s:find('Топор',1,true)
end

local function actionButton()
    if swingCache and swingCache.Parent and swingCache.Visible and
        not swingCache:IsDescendantOf(gui) and
        swingCache.AbsoluteSize.X>8 and swingCache.AbsoluteSize.Y>8 then
        return swingCache,swingName
    end
    if os.clock()-swingScanAt<1.6 then return nil,'ожидание' end
    swingScanAt=os.clock()
    swingCache=nil
    -- Prefer ContextActionService:GetButton; this is the documented touch
    -- action API used by default Roblox mobile buttons.
    local ok,actions=pcall(function() return ContextActionService:GetAllBoundActionInfo() end)
    if ok and type(actions)=='table' then
        for name,info in pairs(actions) do
            if swingMatch(name) or (type(info)=='table' and swingMatch(info.title)) then
                local yes,button=pcall(function() return ContextActionService:GetButton(name) end)
                if yes and button and button:IsA('GuiButton') and button.Visible then
                    swingCache,swingName=button,tostring(name)
                    return button,swingName
                end
            end
        end
    end
    -- Custom GUI: search action text, including nested translated labels.
    local best,bestScore=nil,0
    for _,b in ipairs(playerGui:GetDescendants()) do
        if b:IsA('GuiButton') and not b:IsDescendantOf(gui) and b.Visible and b.AbsoluteSize.X>=20 then
            local text=b.Name..' '..(b:IsA('TextButton') and b.Text or '')
            local bestLocal=swingMatch(text) and 3 or 0
            if bestLocal==0 then
                for _,c in ipairs(b:GetDescendants()) do
                    if (c:IsA('TextLabel') or c:IsA('TextButton')) and swingMatch(c.Text) then
                        bestLocal=4
                        text=c.Text
                        break
                    end
                end
            end
            if bestLocal>bestScore then best,bestScore=b,bestLocal;swingName=text end
        end
    end
    swingCache=best
    return best,best and swingName or 'не найдена'
end

local function virtualTapXY(x,y)
    local ok,vim=pcall(function() return game:GetService('VirtualInputManager') end)
    if ok and vim then
        -- Prioritize native mobile touches; fallback to mouse injection.
        local touchSent=pcall(function()
            vim:SendTouchEvent(47,0,x,y)
            task.wait(0.045)
            vim:SendTouchEvent(47,2,x,y)
        end)
        if touchSent then return true,'эмуляция касания' end
        local mouseSent=pcall(function()
            vim:SendMouseButtonEvent(x,y,0,true,game,0)
            task.wait(0.045)
            vim:SendMouseButtonEvent(x,y,0,false,game,0)
        end)
        if mouseSent then return true,'эмуляция мыши' end
    end
    return false,'Ввод недоступен в Delta'
end
local function virtualTap(button)
    local p,sz=button.AbsolutePosition,button.AbsoluteSize
    return virtualTapXY(math.floor(p.X+sz.X*.5),math.floor(p.Y+sz.Y*.5))
end

-- Manual touch calibration: works even if the game's Swing circle is not
-- discoverable as a GuiButton (e.g. default context actions or localized UI).
connect(UserInputService.InputBegan,function(input)
    if not calibrating or input.UserInputType~=Enum.UserInputType.Touch then return end
    local v=viewport()
    local p=input.Position
    -- Game's swing control is on the right lower half of the screen.
    if p.X<v.X*.5 or p.Y<v.Y*.37 then return end
    calibrationPos=Vector2.new(p.X/v.X,p.Y/v.Y)
    calibrating=false
    status('Кнопка Качели записана. Открой меню и включи автоудары.')
end)

local function swingOnce()
    local button,action=actionButton()
    local tool=equippedAxe()
    if calibrationPos and (swingMethod=='auto' or swingMethod=='virtual') then
        local v=viewport()
        local ok,why=virtualTapXY(math.floor(v.X*calibrationPos.X),math.floor(v.Y*calibrationPos.Y))
        if ok then return true,'записанная кнопка Swing' end
        if swingMethod=='virtual' then return false,why end
    end
    if swingMethod=='tool' then
        if not tool then return false,'Tool отсутствует' end
        return pcall(function() tool:Activate() end),'Tool:Activate'
    end
    if swingMethod=='signal' then
        if button and type(firesignal)=='function' then
            local ok=pcall(function() firesignal(button.Activated) end)
            if ok then return true,'GUI Activated' end
        end
        return false,'сигнал недоступен'
    end
    if button then
        local ok,method=virtualTap(button)
        if ok then return true,method end
        if swingMethod=='virtual' then return false,method end
        if type(firesignal)=='function' then
            local sent=pcall(function() firesignal(button.Activated) end)
            if sent then return true,'GUI Activated' end
        end
    end
    if swingMethod=='auto' and tool then
        return pcall(function() tool:Activate() end),'Tool fallback'
    end
    return false,button and 'кнопка найдена, ввод недоступен' or 'кнопка Swing не найдена'
end

-- Once a player selects Signal, the actual action is still fired through
-- the same game GUI signal that was confirmed working in the previous version.
-- Target selection and aiming are the new parts; no guessed server remotes.
local function resetWoodTarget()
    woodTarget = nil
    woodTargetSince = 0
    woodHitsAtTarget = 0
    woodLastPosition = nil
    woodLastMove = 0
    if woodHighlight then woodHighlight.Adornee = nil end
end
local function restoreAim()
    if restoreCameraState then
        local cam=restoreCameraState.camera
        if cam and cam.Parent then
            pcall(function()
                cam.CameraType=restoreCameraState.cameraType
                if restoreCameraState.cameraSubject then
                    cam.CameraSubject=restoreCameraState.cameraSubject
                end
            end)
        end
        restoreCameraState=nil
    end
    if restoreRotateState and restoreRotateState.hum and restoreRotateState.hum.Parent then
        pcall(function()
            restoreRotateState.hum.AutoRotate=restoreRotateState.value
        end)
    end
    restoreRotateState=nil
    if woodHighlight then woodHighlight.Adornee=nil end
end
stopWoodAim = restoreAim

local function aimTree(target, hum, root, treePos)
    -- Important: the server may cast from the player's look direction OR
    -- from the camera crosshair; aim both. Restore all camera settings on off.
    local focus=Vector3.new(treePos.X,root.Position.Y+2.2,treePos.Z)
    local flat=Vector3.new(focus.X,root.Position.Y,focus.Z)
    if (flat-root.Position).Magnitude>0.3 then
        if not restoreRotateState or restoreRotateState.hum~=hum then
            if restoreRotateState and restoreRotateState.hum and restoreRotateState.hum.Parent then
                pcall(function() restoreRotateState.hum.AutoRotate=restoreRotateState.value end)
            end
            restoreRotateState={hum=hum,value=hum.AutoRotate}
        end
        hum.AutoRotate=false
        root.CFrame=CFrame.lookAt(root.Position,flat)
    end
    if enabled.aim then
        local cam=workspace.CurrentCamera
        if cam then
            if not restoreCameraState or restoreCameraState.camera~=cam then
                restoreCameraState={camera=cam,cameraType=cam.CameraType,cameraSubject=cam.CameraSubject}
            end
            local dir=Vector3.new(focus.X-root.Position.X,0,focus.Z-root.Position.Z)
            if dir.Magnitude>0.2 then
                local desiredPos=root.Position-dir.Unit*8+Vector3.new(0,4,0)
                cam.CameraType=Enum.CameraType.Scriptable
                cam.CFrame=CFrame.lookAt(desiredPos,focus)
            end
        end
    elseif restoreCameraState then
        local cam=restoreCameraState.camera
        if cam and cam.Parent then pcall(function() cam.CameraType=restoreCameraState.cameraType end) end
        restoreCameraState=nil
    end
    if not woodHighlight then
        woodHighlight=create('Highlight',effectFolder,{
            Name='DWH_WoodTarget',FillTransparency=.94,
            OutlineTransparency=0.1,OutlineColor=theme.accent,
            DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        })
    end
    woodHighlight.Adornee=target
end

local function woodTargetPoint(obj, root)
    local p=positionOf(obj)
    if not p then return nil end
    -- Face the trunk at approximately arm height, not the tree crown.
    return Vector3.new(p.X,root.Position.Y+2.2,p.Z)
end

local function chopTick()
    if os.clock()-lastChop < chopInterval then return end
    lastChop=os.clock()
    local _,hum,myRoot=character()
    if not hum or not myRoot or hum.Health<=0 then
        restoreAim()
        status('Дерево: ожидаю персонажа за фермера')
        return
    end
    local pos=woodTarget and positionOf(woodTarget)
    if woodTarget and (not pos or not woodTarget.Parent) then
        resetWoodTarget()
    end
    if not woodTarget then
        local nearest,d=closestTree(enabled.walk and 140 or chopRadius)
        if not nearest then
            restoreAim()
            status('Нет деревьев рядом | распознано объектов '..#cachedTrees)
            return
        end
        woodTarget=nearest
        woodTargetSince=os.clock()
        woodHitsAtTarget=0
        woodLastPosition=myRoot.Position
        woodLastMove=os.clock()
    end
    local focus=woodTargetPoint(woodTarget,myRoot)
    if not focus then resetWoodTarget();return end
    local offset=Vector3.new(focus.X-myRoot.Position.X,0,focus.Z-myRoot.Position.Z)
    local distance=offset.Magnitude
    -- 6 studs is a conservative stand-off so the axe can reach the trunk.
    local approachRadius=chopRadius
    if distance>approachRadius then
        restoreAim()
        if not enabled.walk then
            status('Дерево: цель '..math.floor(distance+.5)..' ст. Включи «Подход»')
            return
        end
        local direction=offset.Unit
        local standOff=Vector3.new(focus.X, myRoot.Position.Y,focus.Z) - direction*5
        hum:MoveTo(standOff)
        if woodLastPosition and (myRoot.Position-woodLastPosition).Magnitude>2.5 then
            woodLastMove=os.clock()
            woodLastPosition=myRoot.Position
        elseif os.clock()-woodLastMove>9 then
            woodBlockedUntil[woodTarget]=os.clock()+20
            resetWoodTarget()
            status('Путь заблокирован: выбираю другое дерево')
            return
        end
        status('К дереву: '..math.floor(distance+.5)..' ст. | автоподход')
        return
    end
    hum:MoveTo(myRoot.Position)
    aimTree(woodTarget,hum,myRoot,focus)
    -- The selected working method is 'signal' by default.
    local ok,method=swingOnce()
    if ok then
        chopAttempts=chopAttempts+1
        woodHitsAtTarget=woodHitsAtTarget+1
    end
    status((ok and 'ЦЕЛЬ → ДЕРЕВО' or 'Удар не отправлен')..' | '..
        math.floor(distance+.5)..' ст. | '..method..' | '..woodHitsAtTarget..' ударов')
    -- If the instance wasn't removed (or it takes a long time to fall), avoid
    -- permanently hitting a single target. Counted swings are NOT confirmed wood.
    if woodHitsAtTarget>=12 or os.clock()-woodTargetSince>18 then
        woodBlockedUntil[woodTarget]=os.clock()+20
        resetWoodTarget()
        status('Цель сменена после ударов. Проверь счётчик древесины.')
    end
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
addButton(1,'Расстояние','Компактная дистанция рядом с именем.',function()
    status(enabled.distance and 'Расстояние включено' or 'Расстояние выключено')
end,'distance')
addButton(1,'Порог HP: > 100','Меняет порог выделения красным: 100 / 120 / 150 / 200.',function(title)
    local values={100,120,150,200}
    local index=table.find(values,hpThreshold) or 1
    hpThreshold=values[index%#values+1]
    title.Text='Порог HP: > '..hpThreshold
    status('Красный — MaxHealth выше '..hpThreshold)
end)
addButton(1,'Дальность ESP: 350 ст.','Ограничивает количество подписей: 180 / 350 / 650 / 1200.',function(title)
    espRangeIndex=espRangeIndex%#espRanges+1
    title.Text='Дальность ESP: '..espRanges[espRangeIndex]..' ст.'
    status('Дальность ESP: '..espRanges[espRangeIndex]..' студ.')
end)
addLine(1,'Зелёный — игрок; красный — предположительно убийца (MaxHealth > порога).',false)

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

addLine(3,'АВТОДОБЫЧА ДЕРЕВА · ЦЕЛЬ',true)
addButton(3,'Автодобыча ближайшего дерева','Подходит, разворачивается к стволу, наводит камеру и бьёт.',function()
    if not enabled.chop then restoreAim();resetWoodTarget() end
    status(enabled.chop and 'Автоцель включена. Режим удара — Сигнал.' or 'Автодобыча выключена')
end,'chop')
addButton(3,'Подход к дереву','Подходит к выбранному стволу без телепорта; по умолчанию ВКЛ.',function()
    resetWoodTarget()
    status(enabled.walk and 'Подход включён' or 'Подход выключен')
end,'walk')
addButton(3,'Наведение камеры','Камера смотрит на выбранный ствол; выключи для ручного обзора.',function()
    if not enabled.aim then restoreAim() end
    status(enabled.aim and 'Автонаведение камеры включено' or 'Автонаведение выключено')
end,'aim')
addButton(3,'Запомнить кнопку «Качели»','Свернёт окно. Один раз нажми кнопку удара в игре справа внизу.',function()
    calibrating=true
    status('Свернул. Коснись кнопки Качели справа внизу 1 раз.')
    shrink()
end)
addButton(3,'Способ удара: Сигнал','Выбор: Авто / виртуальный тап / сигнал / Tool.',function(title)
    swingModeIndex=swingModeIndex%#swingModes+1
    swingMethod=swingModes[swingModeIndex]
    title.Text='Способ удара: '..swingModeLabels[swingModeIndex]
    status('Метод: '..swingModeLabels[swingModeIndex])
end)
addButton(3,'Дистанция удара: 6','Выбор: 5 / 6 / 8 студий до ствола.',function(title)
    chopRadius=(chopRadius==5 and 6 or chopRadius==6 and 8 or 5)
    title.Text='Дистанция удара: '..chopRadius
    status('Дальность: '..chopRadius..' студ.')
end)
addButton(3,'Проверить инструмент','Покажет число найденных деревьев и название топора.',function()
    scanTrees(true)
    local tool=equippedAxe()
    local _,distance=closestTree(200)
    local swing,action=actionButton()
    status('Деревьев: '..#cachedTrees..' | Swing: '..(swing and action or 'нет')..' | Tool: '..(tool and tool.Name or 'нет')..' | Ближ.: '..(distance and math.floor(distance)..' ст.' or 'нет'))
end)
addLine(3,'Сигнал уже работает. Включи автодобычу и подход: скрипт выберет дерево, покажет голубую обводку и наведёт камеру. Проверяй реальный прирост древесины: это не подтверждённый серверный автофарм.',false)

addLine(4,'НАСТРОЙКИ',true)
addButton(4,'Fullbright','Увеличивает освещение, убирает сильную темноту.',function()
    if not enabled.bright then restoreLight() end
    status(enabled.bright and 'Fullbright включён' or 'Fullbright выключен')
end,'bright')
addButton(4,'ТЕСТ КНОПОК','Нажми: строка снизу изменится на «Нажатие работает».',function()
    status('✅ Кнопка работает (v1.8)')
end)
addButton(4,'Свернуть в иконку','Оставляет небольшую кнопку 🌲.',function() shrink() end)
addLine(4,'Только кнопка − для сворачивания. При сворачивании значок закрепляется слева по центру и не уходит за экран.',false)

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
status('v1.8: готово. Вкладка Дерево — автоцель + сигнал.')
