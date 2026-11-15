-- DeepWoods Hub v1.3 FIX | Survive Deep in the Woods
-- UI-first initialization: core buttons and dragging work independently from game automation.
-- Private visual effects only. Does not delete or hide other ScreenGuis.
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local CollectionService = game:GetService('CollectionService')
local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
if type(ENV.DWH_Unload) == 'function' then pcall(ENV.DWH_Unload) end
if type(ENV.DeepWoodsHub_Unload) == 'function' then pcall(ENV.DeepWoodsHub_Unload) end
-- Remove only previous windows created by this project if a past revision died before registering cleanup.
local pg=LP:WaitForChild('PlayerGui')
for _,name in ipairs({'DeepWoodsHub_v12','DeepWoodsHub_OwnWindow','DeepWoodsHub_OnlyOwnGui','DeepWoodsHub_v13_FIX'}) do
    local old=pg:FindFirstChild(name)
    if old and old:IsA('ScreenGui') then pcall(function() old:Destroy() end) end
end

local alive, connections = true, {}
local flags = {esp=false, distance=true, speed=false, noclip=false, bright=false, chop=false, walkToTree=false}
local colors = {
    base=Color3.fromRGB(15,20,32), card=Color3.fromRGB(30,39,57),
    card2=Color3.fromRGB(40,54,77), accent=Color3.fromRGB(76,195,244),
    text=Color3.fromRGB(240,247,255), muted=Color3.fromRGB(156,178,200),
    safe=Color3.fromRGB(75,231,160), danger=Color3.fromRGB(255,77,95),
    yes=Color3.fromRGB(26,147,109), no=Color3.fromRGB(82,91,109)
}
local speedSteps={16,24,32,40,60,90}
local speedIndex=3
local killerThreshold=100
local treeRadius=16
local hitDelay=.6
local statusMessage='Интерфейс готов • v1.3'
local GUI, effects
local speedOwner, speedOriginal
local priorLighting={Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime,
    FogEnd=Lighting.FogEnd, GlobalShadows=Lighting.GlobalShadows}
local partsCollide={}
local espObjects={}
local trees, lastTreeScan={},-100
local swingCount, lastSwing=0,0
local statusLabel

local function safeConnect(signal, fn)
    local c=signal:Connect(fn)
    connections[#connections+1]=c
    return c
end
local function status(s)
    statusMessage=tostring(s)
    if statusLabel and statusLabel.Parent then statusLabel.Text=statusMessage end
end
local function character()
    local ch=LP.Character
    return ch, ch and ch:FindFirstChildOfClass('Humanoid'), ch and ch:FindFirstChild('HumanoidRootPart')
end
local function new(typ,parent,props)
    local obj=Instance.new(typ)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function round(obj,r) new('UICorner',obj,{CornerRadius=UDim.new(0,r or 9)}) end
local function txt(parent,s,size,color,x,y,w,h,extra)
    local prop={Text=s,TextSize=size or 12,TextColor3=color or colors.text,
        Font=Enum.Font.Gotham,BackgroundTransparency=1,BorderSizePixel=0,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
        Active=false,Position=UDim2.fromOffset(x or 0,y or 0),Size=UDim2.new(w or 1,0,0,h or 24)}
    for k,v in pairs(extra or {}) do prop[k]=v end
    return new('TextLabel',parent,prop)
end
local function bindClick(button,callback)
    local last=0
    local function fire()
        if not alive or os.clock()-last < .18 then return end
        last=os.clock()
        local ok,err=pcall(callback)
        if not ok then status('Кнопка: '..tostring(err):sub(1,85)) end
    end
    safeConnect(button.Activated,fire)
    safeConnect(button.MouseButton1Click,fire)
    -- Fallback for executors where Activated/Click is swallowed on mobile.
    safeConnect(button.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch then fire() end
    end)
end
local function viewport()
    local cam=workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(780,390)
end
local function keepInScreen(frame,pos)
    local v=viewport()
    local frameSize=frame.AbsoluteSize
    local x=math.clamp(pos.X,0,math.max(0,v.X-frameSize.X))
    local y=math.clamp(pos.Y,0,math.max(0,v.Y-frameSize.Y))
    frame.Position=UDim2.fromOffset(x,y)
end

-- Only this GUI belongs to this script; never sweep Roblox UI.
GUI=new('ScreenGui',LP:WaitForChild('PlayerGui'),{
    Name='DeepWoodsHub_v13_FIX',ResetOnSpawn=false,DisplayOrder=1050,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,IgnoreGuiInset=false,Enabled=true
})
effects=new('Folder',workspace,{Name='DeepWoodsHub_v13_Visuals'})
local vp=viewport()
local panelW=math.min(365,math.max(260,vp.X-18))
local panelH=math.min(425,math.max(260,vp.Y-16))
local panel=new('Frame',GUI,{
    Name='HubPanel',Size=UDim2.fromOffset(panelW,panelH),
    Position=UDim2.fromOffset(math.floor((vp.X-panelW)/2),math.floor((vp.Y-panelH)/2)),
    BackgroundColor3=colors.base,BorderSizePixel=0,Visible=true,Active=false
})
round(panel,14)
new('UIStroke',panel,{Color=colors.accent,Thickness=1.3,Transparency=.18})
local head=new('Frame',panel,{Size=UDim2.new(1,0,0,47),BackgroundColor3=colors.card,
    BorderSizePixel=0,Active=false})
round(head,12)
-- Header drag area is a TextButton, with minimize and close above it.
local handle=new('TextButton',head,{
    Name='DragArea',Text='🌲  DeepWoods Hub  v1.3',TextSize=14,
    TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,
    TextColor3=colors.text,BackgroundTransparency=1,BorderSizePixel=0,
    Position=UDim2.fromOffset(11,0),Size=UDim2.new(1,-100,1,0),Active=true,
    AutoButtonColor=false,ZIndex=3
})
local minimize=new('TextButton',head,{Text='−',Font=Enum.Font.GothamBold,TextSize=23,
    TextColor3=colors.text,BackgroundColor3=colors.card2,BorderSizePixel=0,
    Position=UDim2.new(1,-75,0,8),Size=UDim2.fromOffset(31,31),ZIndex=7})
round(minimize,8)
local exit=new('TextButton',head,{Text='×',Font=Enum.Font.GothamBold,TextSize=23,
    TextColor3=colors.text,BackgroundColor3=Color3.fromRGB(170,54,67),BorderSizePixel=0,
    Position=UDim2.new(1,-39,0,8),Size=UDim2.fromOffset(31,31),ZIndex=7})
round(exit,8)
local icon=new('TextButton',GUI,{Name='OpenIcon',Text='🌲',TextSize=27,
    Font=Enum.Font.GothamBold,TextColor3=colors.text,BackgroundColor3=colors.base,
    BorderSizePixel=0,Position=UDim2.fromOffset(12,math.floor(vp.Y/2)),
    Size=UDim2.fromOffset(56,56),Visible=false,Active=true,ZIndex=10})
round(icon,16)
new('UIStroke',icon,{Color=colors.accent,Thickness=2})

local function dragSurface(surface,target,canClick)
    local held,inputStart,positionStart=nil,nil,nil
    local moved=false
    safeConnect(surface.InputBegan,function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            held=inp
            inputStart=inp.Position
            positionStart=target.AbsolutePosition
            moved=false
        end
    end)
    local function move(inp)
        if not held or not inputStart or not positionStart then return end
        if inp~=held and not (held.UserInputType==Enum.UserInputType.MouseButton1 and inp.UserInputType==Enum.UserInputType.MouseMovement) and not (held.UserInputType==Enum.UserInputType.Touch and inp.UserInputType==Enum.UserInputType.Touch) then return end
        local delta=inp.Position-inputStart
        if delta.Magnitude>7 then moved=true end
        keepInScreen(target,positionStart+delta)
    end
    safeConnect(UIS.InputChanged,move)
    safeConnect(surface.InputChanged,move)
    safeConnect(UIS.InputEnded,function(inp)
        if held and (inp==held or (held.UserInputType==Enum.UserInputType.MouseButton1 and inp.UserInputType==Enum.UserInputType.MouseButton1) or (held.UserInputType==Enum.UserInputType.Touch and inp.UserInputType==Enum.UserInputType.Touch)) then
            held=nil
            if canClick and not moved then canClick() end
        end
    end)
end
local function shrink()
    icon.Position=UDim2.fromOffset(math.max(5,panel.AbsolutePosition.X),math.max(5,panel.AbsolutePosition.Y))
    panel.Visible=false
    icon.Visible=true
end
local function expand()
    panel.Position=UDim2.fromOffset(math.max(0,icon.AbsolutePosition.X), math.max(0,icon.AbsolutePosition.Y))
    icon.Visible=false
    panel.Visible=true
    keepInScreen(panel,panel.AbsolutePosition)
end
local function restoreSpeed()
    if speedOwner and speedOwner.Parent and speedOriginal~=nil then
        pcall(function() speedOwner.WalkSpeed=speedOriginal end)
    end
    speedOwner=nil;speedOriginal=nil
end
local function restoreLight()
    for k,v in pairs(priorLighting) do pcall(function() Lighting[k]=v end) end
end
local function restoreCollisions()
    for part,value in pairs(partsCollide) do
        if part and part.Parent then pcall(function() part.CanCollide=value end) end
    end
    table.clear(partsCollide)
end
local function clearESP(player)
    local e=espObjects[player]
    if not e then return end
    if e.h then pcall(function() e.h:Destroy() end) end
    if e.bill then pcall(function() e.bill:Destroy() end) end
    espObjects[player]=nil
end
local function unload()
    if not alive then return end
    alive=false
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    for p in pairs(espObjects) do clearESP(p) end
    restoreSpeed();restoreCollisions();restoreLight()
    if effects then pcall(function()effects:Destroy()end) end
    if GUI then pcall(function()GUI:Destroy()end) end
    if ENV.DWH_Unload==unload then ENV.DWH_Unload=nil end
    if ENV.DeepWoodsHub_Unload==unload then ENV.DeepWoodsHub_Unload=nil end
end
ENV.DWH_Unload=unload
ENV.DeepWoodsHub_Unload=unload
-- Bind critical UI handlers BEFORE building any pages.
bindClick(exit,unload)
bindClick(minimize,shrink)
-- Icon opens after a short touch, but never opens while being dragged.
dragSurface(icon,icon,expand)
dragSurface(handle,panel,nil)

local nav=new('Frame',panel,{Position=UDim2.fromOffset(8,53),Size=UDim2.new(1,-16,0,40),
    BackgroundTransparency=1,BorderSizePixel=0,Active=false})
local content=new('ScrollingFrame',panel,{
    Name='CurrentPage',Position=UDim2.fromOffset(8,99),Size=UDim2.new(1,-16,1,-146),
    ScrollBarThickness=3,BorderSizePixel=0,BackgroundTransparency=1,
    ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,0),
    Active=true
})
local layout=new('UIListLayout',content,{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder})
safeConnect(layout:GetPropertyChangedSignal('AbsoluteContentSize'),function()
    if alive then content.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+12) end
end)
local footer=new('Frame',panel,{Position=UDim2.new(0,9,1,-41),Size=UDim2.new(1,-18,0,34),
    BackgroundColor3=colors.card,BorderSizePixel=0})
round(footer,8)
statusLabel=txt(footer,statusMessage,10,colors.muted,9,0,1,34,{
    Size=UDim2.new(1,-18,1,0),TextWrapped=true
})

local function addNote(s)
    local f=new('Frame',content,{Size=UDim2.new(1,-8,0,59),BackgroundColor3=colors.card,
        BorderSizePixel=0,Active=false})
    round(f,9)
    txt(f,s,11,colors.muted,9,4,1,51,{Size=UDim2.new(1,-18,1,-8),TextWrapped=true})
end
local function addTitle(s)
    txt(content,s,13,colors.accent,5,0,1,25,{Size=UDim2.new(1,-9,0,25),Font=Enum.Font.GothamBold})
end
local function addControl(title,description,callback,flag)
    local btn=new('TextButton',content,{
        Name='Control',Text='',Size=UDim2.new(1,-8,0,65),
        BorderSizePixel=0,BackgroundColor3=colors.card,AutoButtonColor=true,Active=true
    })
    round(btn,9)
    txt(btn,title,13,colors.text,10,8,1,21,{
        Size=UDim2.new(1,flag and -83 or -18,0,22),Font=Enum.Font.GothamSemibold
    })
    txt(btn,description,10,colors.muted,10,31,1,29,{
        Size=UDim2.new(1,flag and -83 or -18,0,29),TextWrapped=true,
        TextYAlignment=Enum.TextYAlignment.Top
    })
    local chip
    if flag then
        chip=txt(btn,'ВЫКЛ',10,colors.text,0,0,1,25,{
            BackgroundTransparency=0,BackgroundColor3=colors.no,
            Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Center,
            Size=UDim2.fromOffset(58,26),Position=UDim2.new(1,-66,0,18)
        })
        round(chip,7)
    end
    local function redraw()
        if chip then
            chip.Text=flags[flag] and 'ВКЛ' or 'ВЫКЛ'
            chip.BackgroundColor3=flags[flag] and colors.yes or colors.no
        end
    end
    bindClick(btn,function()
        if flag then flags[flag]=not flags[flag] end
        redraw()
        callback()
    end)
    redraw()
end

local function espTick()
    if not flags.esp then
        for p in pairs(espObjects) do clearESP(p) end
        return 0
    end
    local _,_,me=character()
    local count=0
    local present={}
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP then
            local ch=p.Character
            local hum=ch and ch:FindFirstChildOfClass('Humanoid')
            local part=ch and (ch:FindFirstChild('Head') or ch:FindFirstChild('HumanoidRootPart'))
            if ch and hum and part and hum.Health>0 then
                local e=espObjects[p]
                if not e or e.character~=ch then
                    clearESP(p)
                    local h=new('Highlight',effects,{
                        Name='DWH_ESP',Adornee=ch,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency=.75,OutlineTransparency=0
                    })
                    local bill,label
                    local bOK,bResult=pcall(function()
                        return new('BillboardGui',pg,{
                            Name='DWH_NameAndDistance',Adornee=part,AlwaysOnTop=true,
                            Size=UDim2.fromOffset(180,57),StudsOffsetWorldSpace=Vector3.new(0,3,0),
                            MaxDistance=3000,Enabled=true
                        })
                    end)
                    if bOK then
                        bill=bResult
                        local labelOK,labelResult=pcall(function()
                            local l=new('TextLabel',bill,{
                                Size=UDim2.fromScale(1,1),Font=Enum.Font.GothamBold,TextSize=12,
                                BackgroundColor3=colors.base,BackgroundTransparency=.25,
                                TextColor3=colors.safe,TextStrokeTransparency=.35,
                                TextWrapped=true,BorderSizePixel=0,Active=false
                            })
                            round(l,7)
                            return l
                        end)
                        if labelOK then label=labelResult end
                    end
                    e={character=ch,h=h,bill=bill,label=label}
                    espObjects[p]=e
                end
                local suspect=hum.MaxHealth>killerThreshold
                local color=suspect and colors.danger or colors.safe
                e.h.FillColor=color;e.h.OutlineColor=color
                if e.label then e.label.TextColor3=color end
                local d=me and ((me.Position-part.Position).Magnitude) or nil
                if e.label then e.label.Text=p.DisplayName .. (suspect and ' [>100 HP]' or '') ..'\n' ..
                    'HP '..math.ceil(hum.Health)..'/'..math.ceil(hum.MaxHealth)..
                    (flags.distance and d and ('  |  '..math.floor(d+.5)..' ст.') or '') end
                present[p]=true
                count=count+1
            end
        end
    end
    for p in pairs(espObjects) do if not present[p] then clearESP(p) end end
    return count
end
local function isTree(obj)
    local name=string.lower(obj.Name)
    return name:find('tree',1,true) or name:find('trunk',1,true)
        or name:find('pine',1,true) or name:find('oak',1,true)
        or name:find('birch',1,true) or name:find('spruce',1,true)
        or name:find('дерево',1,true)
end
local function getPos(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA('BasePart') then return obj.Position end
    if obj:IsA('Model') then
        local p=obj:FindFirstChildWhichIsA('BasePart',true)
        return p and p.Position
    end
    return nil
end
local function scanTrees(force)
    if not force and os.clock()-lastTreeScan<6 then return end
    lastTreeScan=os.clock()
    local seen,found={},{}
    local function add(o)
        if #found>=400 or not o or not o.Parent then return end
        if o:IsA('BasePart') and o.Parent:IsA('Model') and isTree(o.Parent) then o=o.Parent end
        if not seen[o] and (o:IsA('Model') or o:IsA('BasePart')) and getPos(o) then
            seen[o]=true;found[#found+1]=o
        end
    end
    for _,tag in ipairs({'Tree','ChoppableTree','HarvestableTree'}) do
        local ok,list=pcall(function() return CollectionService:GetTagged(tag) end)
        if ok then for _,o in ipairs(list) do add(o) end end
    end
    for _,o in ipairs(workspace:GetDescendants()) do
        if isTree(o) and (o:IsA('Model') or o:IsA('BasePart')) then add(o) end
        if #found>=400 then break end
    end
    trees=found
end
local function nearestTree(radius)
    local _,_,me=character()
    if not me then return nil,nil end
    scanTrees(false)
    local best,dist=nil,radius
    for _,o in ipairs(trees) do
        local pos=getPos(o)
        if pos then
            local d=(Vector3.new(me.Position.X,0,me.Position.Z)-Vector3.new(pos.X,0,pos.Z)).Magnitude
            if d<dist then best,dist=o,d end
        end
    end
    return best,dist
end
local function axe()
    local ch,hum=character()
    if not ch or not hum then return nil end
    local function matches(o)
        if not o:IsA('Tool') then return false end
        local name=string.lower(o.Name..' '..o.ToolTip)
        return name:find('axe',1,true) or name:find('hatchet',1,true) or name:find('топор',1,true)
            or name:find('chop',1,true)
    end
    for _,o in ipairs(ch:GetChildren()) do if matches(o) then return o end end
    local bag=LP:FindFirstChild('Backpack')
    if bag then for _,o in ipairs(bag:GetChildren()) do
        if matches(o) then pcall(function()hum:EquipTool(o)end);return o end
    end end
    return nil
end
local function chopTick()
    if os.clock()-lastSwing<hitDelay then return end
    lastSwing=os.clock()
    local ch,hum,me=character()
    if not ch or not hum or not me or hum.Health<=0 then return end
    local tool=axe()
    if not tool then status('Дерево: топор Tool не найден. Проверь инвентарь.') return end
    local tree,dist=nearestTree(flags.walkToTree and 150 or treeRadius)
    if not tree then status('Дерево: целей нет. Объектов в кэше '..#trees) return end
    local pos=getPos(tree)
    if not pos then return end
    if dist>treeRadius then
        if flags.walkToTree then
            pcall(function()hum:MoveTo(pos)end)
            status('Иду к дереву: '..math.floor(dist)..' студий')
        end
        return
    end
    local ok=pcall(function()tool:Activate()end)
    if ok then swingCount=swingCount+1 end
    status('Удары топором: '..swingCount..' | добычу проверь в игре')
end
local function noclipTick()
    local ch=LP.Character
    if not ch then return end
    for _,p in ipairs(ch:GetDescendants()) do
        if p:IsA('BasePart') and p.CanCollide then
            if partsCollide[p]==nil then partsCollide[p]=p.CanCollide end
            p.CanCollide=false
        end
    end
end

local pages={'ESP','Движение','Дерево','Экран'}
local selectedTab=1
local tabButtons={}
local render
local btnW=math.floor((panelW-16-18)/4)
for i,title in ipairs(pages) do
    local idx=i
    local b=new('TextButton',nav,{
        Text=title,TextSize=11,Font=Enum.Font.GothamBold,
        TextColor3=colors.muted,BackgroundColor3=colors.card,BorderSizePixel=0,
        Position=UDim2.fromOffset((i-1)*(btnW+6),0),
        Size=UDim2.fromOffset(btnW,36),AutoButtonColor=true,Active=true
    })
    round(b,8)
    tabButtons[i]=b
    bindClick(b,function()
        selectedTab=idx
        if render then render() end
    end)
end

render=function()
    for _,c in ipairs(content:GetChildren()) do
        if c~=layout then pcall(function()c:Destroy()end) end
    end
    content.CanvasPosition=Vector2.new(0,0)
    for i,b in ipairs(tabButtons) do
        b.BackgroundColor=i==selectedTab and colors.accent or colors.card
        b.TextColor=i==selectedTab and colors.base or colors.muted
    end
    local ok,err=pcall(function()
        if selectedTab==1 then
            addTitle('ИГРОКИ')
            addControl('ESP игроков','Подсветка, имена, HP и расстояние. Нужен включённый ESP.',function()
                if not flags.esp then for p in pairs(espObjects) do clearESP(p) end end
                status(flags.esp and 'ESP включён' or 'ESP выключен')
            end,'esp')
            addControl('Расстояние до игроков','Показывает дистанцию в студиях Roblox.',function()
                status(flags.distance and 'Дистанция включена' or 'Дистанция выключена')
            end,'distance')
            addControl('Порог HP: '..killerThreshold,'Красный = возможный убийца, если MaxHealth выше порога.',function()
                local steps={100,120,150,200}
                local i=table.find(steps,killerThreshold) or 1
                killerThreshold=steps[i%#steps+1]
                render()
                status('Порог подозрения: > '..killerThreshold..' HP')
            end)
            addNote('Красный — возможный убийца (по HP), зелёный — остальные. Роль точно не определяется.')
        elseif selectedTab==2 then
            addTitle('ПЕРЕДВИЖЕНИЕ')
            addControl('Быстрый бег','Включает выбранную скорость перемещения.',function()
                if not flags.speed then restoreSpeed() end
                status(flags.speed and 'Быстрый бег включён' or 'Быстрый бег выключен')
            end,'speed')
            addControl('Скорость: '..speedSteps[speedIndex],'Выбор: 16 / 24 / 32 / 40 / 60 / 90.',function()
                speedIndex=speedIndex%#speedSteps+1
                render()
                status('Скорость: '..speedSteps[speedIndex])
            end)
            addControl('Noclip','Локально отключает столкновения частей персонажа.',function()
                if not flags.noclip then restoreCollisions() end
                status(flags.noclip and 'Noclip включён' or 'Noclip выключен')
            end,'noclip')
            addNote('Сервер игры может возвращать исходные значения скорости и столкновений.')
        elseif selectedTab==3 then
            addTitle('ДОБЫЧА ДЕРЕВА')
            addControl('Авторубка (тест)','Ищет ближайшее дерево и пробует активировать топор.',function()
                status(flags.chop and 'Авторубка запущена (тест)' or 'Авторубка выключена')
            end,'chop')
            addControl('Автоподход к дереву','Идёт к найденному дереву без телепорта.',function()
                status(flags.walkToTree and 'Автоподход включён' or 'Автоподход выключен')
            end,'walkToTree')
            addControl('Радиус: '..treeRadius..' ст.','Переключает 10 / 16 / 22 студии.',function()
                treeRadius=treeRadius==10 and 16 or treeRadius==16 and 22 or 10
                render()
            end)
            addControl('Проверка дерева и топора','Выводит число распознанных деревьев и название топора.',function()
                scanTrees(true)
                local tool=axe()
                local _,d=nearestTree(200)
                status('Деревьев: '..#trees..' | Топор: '..(tool and tool.Name or 'нет')..' | дистанция: '..(d and math.floor(d) or 'нет'))
            end)
            addNote('Только тест: Tool:Activate() не гарантирует выдачу древесины сервером. Если не рубит — нужны данные механики игры.')
        elseif selectedTab==4 then
            addTitle('ЭКРАН И НАСТРОЙКИ')
            addControl('Fullbright','Увеличивает яркость и снижает эффект темноты.',function()
                if not flags.bright then restoreLight() end
                status(flags.bright and 'Fullbright включён' or 'Fullbright выключен')
            end,'bright')
            addControl('Проверка интерфейса','Нажми: должен появиться текст «Кнопки работают».',function()
                status('✅ Кнопки работают! Версия 1.3')
            end)
            addControl('Свернуть в иконку 🌲','Оставить маленькую плавающую кнопку вместо окна.',shrink)
            addControl('Закрыть скрипт полностью','Остановить эффекты и удалить только наше окно.',unload)
            addNote('Окошко передвигается за названием сверху. Кнопка × закрывает всё. Roblox GUI не удаляется.')
        end
    end)
    if not ok then status('Ошибка вкладки: '..tostring(err):sub(1,110)) end
    content.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+12)
end
render()

safeConnect(RunService.Stepped,function()
    if alive and flags.noclip then pcall(noclipTick) end
end)
task.spawn(function()
    local espTime=0
    local statusTime=0
    while alive do
        task.wait(.25)
        if not alive then break end
        local _,hum=character()
        if flags.speed and hum then
            if hum~=speedOwner then
                restoreSpeed();speedOwner=hum;speedOriginal=hum.WalkSpeed
            end
            pcall(function()hum.WalkSpeed=speedSteps[speedIndex]end)
        elseif speedOwner then restoreSpeed() end
        if flags.bright then pcall(function()
            Lighting.Brightness=3
            Lighting.ClockTime=14
            Lighting.FogEnd=100000
            Lighting.GlobalShadows=false
        end) end
        if flags.chop then
            local ok,err=pcall(chopTick)
            if not ok then status('Ошибка дерева: '..tostring(err):sub(1,90)) end
        end
        if os.clock()>espTime then
            espTime=os.clock()+.45
            local ok,count=pcall(espTick)
            if not ok then status('Ошибка ESP: '..tostring(count):sub(1,90))
            elseif flags.esp and not flags.chop and os.clock()>statusTime then
                statusTime=os.clock()+3
                status('ESP: игроков '..count..' • >'..killerThreshold..' HP = красный')
            end
        end
    end
end)
status('v1.3 FIX • кнопки, вкладки и закрытие готовы')
