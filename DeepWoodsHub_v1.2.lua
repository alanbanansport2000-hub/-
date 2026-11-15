-- DeepWoods Hub v1.2 | Survive Deep in the Woods
-- Mobile UI with ESP, movement, light and new cautious wood-cutting automation.
-- No broad ScreenGui deletion, no outside code loaders, no key system.
-- Killer classification is a HEURISTIC: MaxHealth > configured threshold, not a confirmed role.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local Lighting = game:GetService('Lighting')
local CollectionService = game:GetService('CollectionService')
local LocalPlayer = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

if type(ENV.DWH_Unload) == 'function' then
    pcall(ENV.DWH_Unload)
end

local alive = true
local connections = {}
local visuals = {}
local originalCollisions = {}
local screen = nil
local effectFolder = nil
local speedHumanoid = nil
local originalSpeed = nil
local originalLight = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient
}
local enabled = { esp = false, distance = true, fullbright = false, speed = false, noclip = false, chop = false, approach = false }
local killerThreshold = 100
local speedSteps = {16,24,32,40,60,90}
local speedIndex = 3
local displayRange = 2500
local statusText = 'Готово. Включи нужные функции.'
local chopRangeSteps = {8, 11, 14, 18, 20}
local chopRangeIndex = 3
local chopDelaySteps = {0.28, 0.45, 0.7, 1.0}
local chopDelayIndex = 2
local treeCache, treeScanAt, treeScanCount = {}, 0, 0
local chopNext, swings = 0, 0
local lastChopStatus = ''
local treeCurrent, treeStuckAt, treeStuckPos = nil, 0, nil
local panelStatusLast = 0

local C = {
    bg = Color3.fromRGB(14,18,29),
    panel = Color3.fromRGB(22,29,43),
    card = Color3.fromRGB(33,42,59),
    cardHi = Color3.fromRGB(42,54,76),
    border = Color3.fromRGB(65,83,115),
    text = Color3.fromRGB(244,247,252),
    muted = Color3.fromRGB(163,178,201),
    accent = Color3.fromRGB(70,185,247),
    active = Color3.fromRGB(40,156,117),
    inactive = Color3.fromRGB(88,95,113),
    dangerous = Color3.fromRGB(255,79,95),
    safe = Color3.fromRGB(86,221,175)
}

local function track(signal, fn)
    local connection = signal:Connect(fn)
    connections[#connections + 1] = connection
    return connection
end

local function character()
    local c = LocalPlayer.Character
    return c, c and c:FindFirstChildOfClass('Humanoid'), c and c:FindFirstChild('HumanoidRootPart')
end

local function restoreLight()
    for key, value in pairs(originalLight) do
        pcall(function() Lighting[key] = value end)
    end
end

local function restoreCollisions()
    for part, old in pairs(originalCollisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = old end)
        end
    end
    table.clear(originalCollisions)
end

local function restoreSpeed()
    if speedHumanoid and speedHumanoid.Parent and originalSpeed ~= nil then
        pcall(function() speedHumanoid.WalkSpeed = originalSpeed end)
    end
    speedHumanoid = nil
    originalSpeed = nil
end

local function clearVisual(player)
    local data = visuals[player]
    if not data then return end
    if data.h then pcall(function() data.h:Destroy() end) end
    if data.bill then pcall(function() data.bill:Destroy() end) end
    visuals[player] = nil
end

local function createVisual(player, model)
    clearVisual(player)
    local anchor = model:FindFirstChild('Head') or model:FindFirstChild('HumanoidRootPart')
    if not anchor then return nil end

    local h = Instance.new('Highlight')
    h.Name = 'DWH_PlayerHighlight'
    h.Adornee = model
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillTransparency = .82
    h.OutlineTransparency = .05
    h.Parent = effectFolder

    local billboard = Instance.new('BillboardGui')
    billboard.Name = 'DWH_PlayerDistance'
    billboard.Adornee = anchor
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(220,65)
    billboard.StudsOffset = Vector3.new(0,3.1,0)
    billboard.MaxDistance = displayRange
    billboard.Parent = effectFolder

    local name = Instance.new('TextLabel')
    name.Name = 'Info'
    name.BackgroundColor3 = Color3.fromRGB(11,17,27)
    name.BackgroundTransparency = .22
    name.BorderSizePixel = 0
    name.Size = UDim2.fromScale(1,1)
    name.Text = ''
    name.TextColor3 = C.safe
    name.TextStrokeColor3 = Color3.new(0,0,0)
    name.TextStrokeTransparency = .2
    name.TextSize = 12
    name.Font = Enum.Font.GothamBold
    name.TextWrapped = true
    name.Parent = billboard
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0,8)
    corner.Parent = name
    local stroke = Instance.new('UIStroke')
    stroke.Thickness = 1
    stroke.Transparency = .2
    stroke.Parent = name

    local data = {model=model,h=h,bill=bill,label=name,stroke=stroke}
    visuals[player] = data
    return data
end

local function refreshESP()
    if not enabled.esp then
        for player in pairs(visuals) do clearVisual(player) end
        return 0, nil
    end
    local _, _, root = character()
    local visible = {}
    local count, killerDistance = 0, nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local ch = player.Character
            local hum = ch and ch:FindFirstChildOfClass('Humanoid')
            local hrp = ch and ch:FindFirstChild('HumanoidRootPart')
            if ch and hum and hrp and hum.Health > 0 then
                local distance = root and (root.Position-hrp.Position).Magnitude or 0
                if not root or distance <= displayRange then
                    local data = visuals[player]
                    if not data or data.model ~= ch or not data.h.Parent or not data.bill.Parent then
                        data = createVisual(player,ch)
                    end
                    if data then
                        local hp, maxHp = math.ceil(hum.Health), math.ceil(hum.MaxHealth)
                        local suspect = hum.MaxHealth > killerThreshold
                        local color = suspect and C.dangerous or C.safe
                        data.h.FillColor = color
                        data.h.OutlineColor = color
                        data.label.TextColor3 = color
                        data.stroke.Color = color
                        data.bill.Enabled = true
                        data.bill.MaxDistance = displayRange
                        local meters = tostring(math.floor(distance+.5)) .. ' ст.'
                        local kind = suspect and 'ВОЗМОЖНЫЙ УБИЙЦА' or 'Игрок'
                        if enabled.distance and root then
                            data.label.Text = player.DisplayName .. ' | ' .. kind .. '\n' ..
                                'HP ' .. hp .. '/' .. maxHp .. '  •  ' .. meters
                        else
                            data.label.Text = player.DisplayName .. ' | ' .. kind .. '\nHP ' .. hp .. '/' .. maxHp
                        end
                        visible[player] = true
                        count = count + 1
                        if suspect and root and (not killerDistance or distance < killerDistance) then
                            killerDistance = distance
                        end
                    end
                end
            end
        end
    end
    for player in pairs(visuals) do
        if not visible[player] then clearVisual(player) end
    end
    return count, killerDistance
end

local function applyNoclip()
    local ch = LocalPlayer.Character
    if not ch then return end
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA('BasePart') and part.CanCollide then
            if originalCollisions[part] == nil then originalCollisions[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end

-- Wood automation uses ordinary character movement and the equipped axe Tool.
-- The game's server decides whether a chop actually awards wood.
local TREE_WORDS = {'tree','trunk','oak','pine','birch','spruce','willow','choptree','дерево','ствол'}
local function isNamedTree(obj)
    local n = string.lower(obj.Name)
    for _, word in ipairs(TREE_WORDS) do
        if string.find(n,word,1,true) then return true end
    end
    return false
end
local function treePosition(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA('BasePart') then return obj.Position end
    if obj:IsA('Model') then
        local ok, pivot = pcall(function() return obj:GetPivot() end)
        if ok then return pivot.Position end
        local part = obj:FindFirstChildWhichIsA('BasePart',true)
        return part and part.Position
    end
    return nil
end
local function treeAlive(obj)
    if not obj or not obj.Parent then return false end
    for _,key in ipairs({'Health','TreeHealth','HP','WoodHealth'}) do
        local ok,val=pcall(function() return obj:GetAttribute(key) end)
        if ok and type(val)=='number' and val<=0 then return false end
    end
    return true
end
local function scanTrees(force)
    if not force and os.clock()-treeScanAt < 5 then return end
    treeScanAt=os.clock()
    local seen={}
    local found={}
    local function consider(obj)
        if #found>=650 or not obj or not obj.Parent or not treeAlive(obj) then return end
        if obj:IsA('BasePart') and obj.Parent and obj.Parent:IsA('Model') and isNamedTree(obj.Parent) then
            obj=obj.Parent
        end
        if (obj:IsA('BasePart') or obj:IsA('Model')) and not seen[obj] and treePosition(obj) then
            seen[obj]=true
            found[#found+1]=obj
        end
    end
    for _,tag in ipairs({'Tree','Trees','Choppable','ChoppableTree','HarvestableTree'}) do
        local ok,tagged=pcall(function() return CollectionService:GetTagged(tag) end)
        if ok then for _,obj in ipairs(tagged) do consider(obj) end end
    end
    local ok,objects=pcall(function() return workspace:GetDescendants() end)
    if ok then
        for _,obj in ipairs(objects) do
            if isNamedTree(obj) then consider(obj) end
            if #found>=650 then break end
        end
    end
    treeCache=found
    treeScanCount=#found
end
local function closestTree(maxDistance)
    local _,_,rootPart=character()
    if not rootPart then return nil,nil end
    scanTrees(false)
    local best,dist=nil,maxDistance
    for _,obj in ipairs(treeCache) do
        if treeAlive(obj) then
            local at=treePosition(obj)
            if at then
                local d=(Vector3.new(rootPart.Position.X,0,rootPart.Position.Z)-Vector3.new(at.X,0,at.Z)).Magnitude
                if d<dist then best,dist=obj,d end
            end
        end
    end
    return best,dist
end
local function findAxe()
    local ch,hum=character()
    if not ch or not hum then return nil end
    local function isAxe(t)
        if not t:IsA('Tool') then return false end
        local n=string.lower(t.Name)
        return n:find('axe',1,true) or n:find('hatchet',1,true) or n:find('топор',1,true)
    end
    for _,tool in ipairs(ch:GetChildren()) do if isAxe(tool) then return tool end end
    local bag=LocalPlayer:FindFirstChild('Backpack')
    if bag then for _,tool in ipairs(bag:GetChildren()) do
        if isAxe(tool) then
            pcall(function() hum:EquipTool(tool) end)
            return tool
        end
    end end
    return nil
end
local function stopChopMovement()
    local _,hum,rootPart=character()
    if hum and rootPart then pcall(function() hum:MoveTo(rootPart.Position) end) end
    treeCurrent=nil
    treeStuckAt=0
    treeStuckPos=nil
end
local function chopTick()
    if os.clock()<chopNext then return end
    chopNext=os.clock()+chopDelaySteps[chopDelayIndex]
    local _,hum,rootPart=character()
    if not hum or not rootPart or hum.Health<=0 then
        lastChopStatus='Рубка: ожидаю живого персонажа'
        return
    end
    local axe=findAxe()
    if not axe then
        lastChopStatus='Рубка: топор (Tool) не найден в руках/рюкзаке'
        return
    end
    local radius=chopRangeSteps[chopRangeIndex]
    local obj,dist=closestTree(enabled.approach and 200 or radius)
    if not obj then
        lastChopStatus='Рубка: в радиусе деревьев нет; найдено '..treeScanCount
        return
    end
    local at=treePosition(obj)
    if not at then return end
    if dist>radius then
        if enabled.approach then
            -- No teleport: normal MoveTo. Stop trying an inaccessible tree after 9s.
            if treeCurrent~=obj then
                treeCurrent=obj
                treeStuckAt=os.clock()
                treeStuckPos=rootPart.Position
            end
            if treeStuckPos and (rootPart.Position-treeStuckPos).Magnitude>5 then
                treeStuckAt=os.clock()
                treeStuckPos=rootPart.Position
            elseif os.clock()-treeStuckAt>9 then
                lastChopStatus='Дерево недоступно: переместись ближе вручную'
                return
            end
            pcall(function() hum:MoveTo(at) end)
            lastChopStatus='Иду к дереву: '..math.floor(dist+0.5)..' студ.'
        end
        return
    end
    if enabled.approach then
        pcall(function() hum:MoveTo(rootPart.Position) end)
    end
    -- Face the tree to help tools whose hit detection depends on character direction.
    local flat=Vector3.new(at.X,rootPart.Position.Y,at.Z)
    if (flat-rootPart.Position).Magnitude>0.15 then
        pcall(function() rootPart.CFrame=CFrame.lookAt(rootPart.Position,flat) end)
    end
    local ok=pcall(function() axe:Activate() end)
    if ok then swings=swings+1 end
    lastChopStatus='Дерево: '..math.floor(dist+0.5)..' ст. | ударов '..swings..' | ресурс проверь'
end

local function make(className,parent,props)
    local o = Instance.new(className)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function round(parent,radius)
    return make('UICorner',parent,{CornerRadius=UDim.new(0,radius or 10)})
end
local function stroke(parent,color,thickness)
    return make('UIStroke',parent,{Color=color or C.border,Thickness=thickness or 1,Transparency=.12})
end
local function label(parent,text,size,color,props)
    local defaults = {
        Text=text,TextColor3=color or C.text,Font=Enum.Font.Gotham,
        TextSize=size,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,BorderSizePixel=0
    }
    for k,v in pairs(props or {}) do defaults[k]=v end
    return make('TextLabel',parent,defaults)
end

screen = make('ScreenGui',LocalPlayer:WaitForChild('PlayerGui'),{
    Name='DeepWoodsHub_v12',ResetOnSpawn=false,IgnoreGuiInset=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=870
})
effectFolder = make('Folder',workspace,{Name='DeepWoodsHub_PlayerEffects'})

local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(760,390)
local panelW = math.min(355,math.max(260,viewport.X-30))
local panelH = math.min(345,math.max(250,viewport.Y-35))

local panel = make('Frame',screen,{
    Name='MainWindow',BackgroundColor3=C.panel,BorderSizePixel=0,
    Size=UDim2.fromOffset(panelW,panelH),
    Position=UDim2.new(.5,-math.floor(panelW/2),.5,-math.floor(panelH/2)),
    Active=true,Visible=true
})
round(panel,14);stroke(panel,C.border,1.5)
local header = make('Frame',panel,{
    Size=UDim2.new(1,0,0,46),BackgroundColor3=C.bg,BorderSizePixel=0,Active=true
})
round(header,14)
local accentLine = make('Frame',header,{
    Position=UDim2.new(0,0,1,-2),Size=UDim2.new(1,0,0,2),
    BackgroundColor3=C.accent,BorderSizePixel=0
})
label(header,'🌲  DeepWoods Hub',15,C.text,{
    Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-97,1,0),
    Font=Enum.Font.GothamBold
})
local version = label(header,'v1.2',10,C.accent,{
    TextXAlignment=Enum.TextXAlignment.Right,
    Position=UDim2.new(1,-140,0,2),Size=UDim2.fromOffset(36,42)
})
local minimize = make('TextButton',header,{
    Text='−',TextSize=22,Font=Enum.Font.GothamBold,TextColor3=C.text,
    BackgroundColor3=C.cardHi,BorderSizePixel=0,
    Position=UDim2.new(1,-71,0,9),Size=UDim2.fromOffset(29,28)
})
round(minimize,7)
local close = make('TextButton',header,{
    Text='×',TextSize=22,Font=Enum.Font.GothamBold,TextColor3=C.text,
    BackgroundColor3=Color3.fromRGB(158,56,68),BorderSizePixel=0,
    Position=UDim2.new(1,-37,0,9),Size=UDim2.fromOffset(29,28)
})
round(close,7)

local bubble = make('TextButton',screen,{
    Name='FloatingIcon',Text='🌲',TextSize=25,Font=Enum.Font.GothamBold,
    TextColor3=C.text,BackgroundColor3=C.bg,BorderSizePixel=0,
    Size=UDim2.fromOffset(52,52),Position=UDim2.new(0,14,.45,0),
    Active=true,Visible=false,AutoButtonColor=true
})
round(bubble,16);stroke(bubble,C.accent,2)

local tabstrip = make('Frame',panel,{
    BackgroundTransparency=1,Size=UDim2.new(1,-16,0,40),Position=UDim2.fromOffset(8,52)
})
local tabLayout = make('UIListLayout',tabstrip,{
    FillDirection=Enum.FillDirection.Horizontal,
    HorizontalAlignment=Enum.HorizontalAlignment.Center,
    Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder
})
local tabNames = {'ESP','Движение','Дерево','Экран','Настр.'}
local tabButtons = {}
local pages = {}

for i, name in ipairs(tabNames) do
    local w = math.floor((panelW-16-20)/5)
    local button = make('TextButton',tabstrip,{
        Name='Tab_'..i,Text=name,TextSize=10,Font=Enum.Font.GothamBold,
        TextColor3=C.muted,BackgroundColor3=C.card,BorderSizePixel=0,
        Size=UDim2.fromOffset(w,36),LayoutOrder=i,AutoButtonColor=true
    })
    round(button,8)
    tabButtons[i]=button
    local page = make('ScrollingFrame',panel,{
        Name='Page_'..i,BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(9,97),
        Size=UDim2.new(1,-18,1,-146),
        ScrollBarThickness=3,ScrollingDirection=Enum.ScrollingDirection.Y,
        CanvasSize=UDim2.fromOffset(0,0),Visible=false
    })
    local layout = make('UIListLayout',page,{
        Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder
    })
    track(layout:GetPropertyChangedSignal('AbsoluteContentSize'),function()
        if alive then page.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+8) end
    end)
    pages[i]=page
end

local footer = make('Frame',panel,{
    BackgroundColor3=C.bg,BorderSizePixel=0,
    Size=UDim2.new(1,-18,0,37),Position=UDim2.new(0,9,1,-43)
})
round(footer,8)
local status = label(footer,statusText,11,C.muted,{
    Position=UDim2.fromOffset(9,0),Size=UDim2.new(1,-16,1,0),
    TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Center
})
local function statusSet(s)
    statusText = tostring(s)
    if status and status.Parent then status.Text = statusText end
end

local function section(page,s)
    return label(page,s,12,C.accent,{
        Font=Enum.Font.GothamBold,Size=UDim2.new(1,-8,0,22)
    })
end
local function info(page,s)
    local frame = make('Frame',page,{
        BackgroundColor3=C.card,BorderSizePixel=0,Size=UDim2.new(1,-7,0,58)
    })
    round(frame,8)
    label(frame,s,11,C.muted,{
        Position=UDim2.fromOffset(11,5),Size=UDim2.new(1,-22,1,-10),TextWrapped=true,
        TextYAlignment=Enum.TextYAlignment.Center
    })
    return frame
end

local function toggle(page,title,description,key,onchange)
    local cell=make('TextButton',page,{
        BackgroundColor3=C.card,BorderSizePixel=0,Text='',
        Size=UDim2.new(1,-7,0,61),AutoButtonColor=true
    })
    round(cell,9)
    label(cell,title,12,C.text,{
        Font=Enum.Font.GothamSemibold,Position=UDim2.fromOffset(11,8),
        Size=UDim2.new(1,-88,0,21)
    })
    label(cell,description,10,C.muted,{
        Position=UDim2.fromOffset(11,30),Size=UDim2.new(1,-88,0,24),
        TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top
    })
    local chip=make('TextLabel',cell,{
        BackgroundColor3=C.inactive,TextColor3=C.text,
        Text='ВЫКЛ',TextSize=10,Font=Enum.Font.GothamBold,
        Size=UDim2.fromOffset(59,25),Position=UDim2.new(1,-67,0,18),
        BorderSizePixel=0
    })
    round(chip,7)
    local function redraw()
        chip.Text=enabled[key] and 'ВКЛ' or 'ВЫКЛ'
        chip.BackgroundColor3=enabled[key] and C.active or C.inactive
    end
    track(cell.Activated,function()
        if not alive then return end
        enabled[key]=not enabled[key]
        redraw()
        if onchange then pcall(onchange,enabled[key]) end
    end)
    redraw()
    return cell
end

local function action(page,title,description,callback)
    local cell=make('TextButton',page,{
        BackgroundColor3=C.card,BorderSizePixel=0,Text='',
        Size=UDim2.new(1,-7,0,59)
    })
    round(cell,9)
    local titleLabel=label(cell,title,12,C.text,{
        Font=Enum.Font.GothamSemibold,Position=UDim2.fromOffset(11,6),
        Size=UDim2.new(1,-22,0,23)
    })
    label(cell,description,10,C.muted,{
        Position=UDim2.fromOffset(11,29),Size=UDim2.new(1,-22,0,25),
        TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true
    })
    track(cell.Activated,function()if alive then pcall(callback,titleLabel) end end)
    return cell
end

section(pages[1],'ИГРОКИ')
toggle(pages[1],'ESP игроков','Подсветка сквозь стены, имена и HP.','esp',function(value)
    if not value then for p in pairs(visuals) do clearVisual(p) end end
    statusSet(value and 'ESP включён' or 'ESP выключен')
end)
toggle(pages[1],'Расстояние до игрока','Показывать дистанцию в студиях Roblox.','distance')
action(pages[1],'Порог убийцы: > 100 HP','Коснись, чтобы поменять порог подсветки.',function(l)
    local options={100,120,150,200}
    local index=table.find(options,killerThreshold) or 1
    killerThreshold=options[index%#options+1]
    l.Text='Порог убийцы: > '..killerThreshold..' HP'
    statusSet('КРАСНЫЙ = MaxHealth выше '..killerThreshold..' (это предположение)')
end)
info(pages[1],'🔴 Красный: предполагаемый убийца (MaxHealth > порога).\n🟢 Зелёный: остальные. Это НЕ проверка роли игры.')

section(pages[2],'ПЕРЕДВИЖЕНИЕ')
toggle(pages[2],'Быстрый бег','Изменение скорости персонажа.','speed',function(value)
    if not value then restoreSpeed() end
end)
action(pages[2],'Скорость: 32','Нажимай, чтобы выбрать 16 / 24 / 32 / 40 / 60 / 90.',function(l)
    speedIndex=speedIndex%#speedSteps+1
    l.Text='Скорость: '..speedSteps[speedIndex]
    statusSet('Установлена скорость '..speedSteps[speedIndex])
end)
toggle(pages[2],'Noclip','Проход через стены и предметы.','noclip',function(value)
    if not value then restoreCollisions() end
end)
info(pages[2],'Скорость и Noclip могут ограничиваться сервером игры. Закрытие меню восстанавливает изменения.')

section(pages[3],'ДОБЫЧА ДЕРЕВЬЕВ')
toggle(pages[3],'Автоматическая рубка','Берёт топор, ищет дерево и пытается рубить.','chop',function(value)
    if not value then
        if enabled.approach then stopChopMovement() end
        statusSet('Рубка выключена')
    else
        scanTrees(true)
        statusSet('Рубка включена. Найдено деревьев: '..treeScanCount)
    end
end)
toggle(pages[3],'Сам подходить к деревьям','Идёт обычным шагом, без телепорта.','approach',function(value)
    if not value then stopChopMovement() end
end)
action(pages[3],'Дальность рубки: 14 студ.','Выбор: 8 / 11 / 14 / 18 / 20 студий.',function(l)
    chopRangeIndex=chopRangeIndex%#chopRangeSteps+1
    l.Text='Дальность рубки: '..chopRangeSteps[chopRangeIndex]..' студ.'
end)
action(pages[3],'Интервал ударов: 0.45 с','Выбор: 0.28 / 0.45 / 0.7 / 1 сек.',function(l)
    chopDelayIndex=chopDelayIndex%#chopDelaySteps+1
    l.Text=string.format('Интервал ударов: %.2f с',chopDelaySteps[chopDelayIndex])
end)
action(pages[3],'Проверить деревья и топор','Диагностика: количество, инструмент, ближайшая цель.',function()
    scanTrees(true)
    local obj,dist=closestTree(200)
    local tool=findAxe()
    statusSet('Деревья: '..treeScanCount..' | Топор: '..(tool and tool.Name or 'нет')..' | ближ.: '..(dist and math.floor(dist)..' ст.' or 'нет'))
end)
info(pages[3],'Функция пробует рубить через обычный Tool:Activate(). Это НЕ подтверждённый серверный автофарм: проверяй прирост древесины. Если счётчик не растёт — сообщи название топора и результат диагностики.')

section(pages[4],'ОСВЕЩЕНИЕ')
toggle(pages[4],'Fullbright','Светлая картинка, меньше темноты и тумана.','fullbright',function(value)
    if not value then restoreLight() end
end)
info(pages[4],'Fullbright меняет освещение только на твоём устройстве. После выключения прежние настройки возвращаются.')

section(pages[5],'УПРАВЛЕНИЕ')
info(pages[5],'🌲 Кнопка «−» превращает окно в маленькую иконку. Её можно перетаскивать. Нажатие открывает меню обратно.')
info(pages[5],'× Закрыть — полностью остановить этот скрипт, убрать только его ESP и окно. Интерфейс Roblox не затрагивается.')
action(pages[5],'Полностью закрыть DeepWoods Hub','Выключить функции и удалить только это меню.',function()
    if type(ENV.DWH_Unload)=='function' then ENV.DWH_Unload() end
end)

local activeTab = 1
local function selectTab(index)
    activeTab=index
    for i,p in ipairs(pages) do
        p.Visible=(i==index)
        tabButtons[i].BackgroundColor = i==index and C.accent or C.card
        tabButtons[i].TextColor3 = i==index and C.bg or C.muted
    end
end
for i,b in ipairs(tabButtons) do
    local index=i
    track(b.Activated,function() if alive then selectTab(index) end end)
end
selectTab(1)

local bubbleIgnoreClickUntil = 0
local function makeDraggable(handle, target, isBubble)
    local dragging=false
    local activeInput=nil
    local startPoint=nil
    local startPosition=nil
    local moved=false
    track(handle.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            moved=false
            activeInput=input
            startPoint=input.Position
            startPosition=target.Position
        end
    end)
    track(UIS.InputChanged,function(input)
        if not dragging or not startPoint or not startPosition then return end
        if input==activeInput or (activeInput and activeInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseMovement) then
            local diff=input.Position-startPoint
            if diff.Magnitude>8 then moved=true end
            target.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+diff.X,
                startPosition.Y.Scale,startPosition.Y.Offset+diff.Y)
        end
    end)
    track(UIS.InputEnded,function(input)
        if dragging and (input==activeInput or (activeInput and
            activeInput.UserInputType==Enum.UserInputType.MouseButton1 and
            input.UserInputType==Enum.UserInputType.MouseButton1)) then
            dragging=false
            if isBubble and moved then bubbleIgnoreClickUntil=os.clock()+.35 end
        end
    end)
end
makeDraggable(header,panel,false)
makeDraggable(bubble,bubble,true)

track(minimize.Activated,function()
    if not alive then return end
    bubble.Position=panel.Position
    panel.Visible=false
    bubble.Visible=true
end)
track(bubble.Activated,function()
    if not alive or os.clock()<bubbleIgnoreClickUntil then return end
    local p=bubble.AbsolutePosition
    local size=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(760,390)
    local x=math.clamp(p.X,5,math.max(5,size.X-panelW-5))
    local y=math.clamp(p.Y,5,math.max(5,size.Y-panelH-5))
    panel.Position=UDim2.fromOffset(x,y)
    bubble.Visible=false
    panel.Visible=true
end)

local function unload()
    if not alive then return end
    alive=false
    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    for player in pairs(visuals) do clearVisual(player) end
    restoreSpeed()
    restoreCollisions()
    restoreLight()
    if enabled.approach then stopChopMovement() end
    if effectFolder then pcall(function() effectFolder:Destroy() end) end
    if screen then pcall(function() screen:Destroy() end) end
    if ENV.DWH_Unload==unload then ENV.DWH_Unload=nil end
end
ENV.DWH_Unload=unload
track(close.Activated,unload)

track(RunService.Stepped,function()
    if alive and enabled.noclip then pcall(applyNoclip) end
end)

task.spawn(function()
    local nextESP=0
    while alive do
        task.wait(.25)
        if not alive then return end
        local _,hum = character()
        if enabled.speed and hum then
            if speedHumanoid~=hum then
                restoreSpeed()
                speedHumanoid=hum
                originalSpeed=hum.WalkSpeed
            end
            pcall(function() hum.WalkSpeed=speedSteps[speedIndex] end)
        elseif originalSpeed~=nil then
            restoreSpeed()
        end
        if enabled.chop then
            local ok,err=pcall(chopTick)
            if not ok then lastChopStatus='Ошибка рубки: '..tostring(err):sub(1,90) end
            if os.clock()-panelStatusLast>1.5 then
                panelStatusLast=os.clock()
                statusSet(lastChopStatus)
            end
        end
        if enabled.fullbright then
            pcall(function()
                Lighting.Brightness=3
                Lighting.ClockTime=14
                Lighting.FogEnd=100000
                Lighting.GlobalShadows=false
                Lighting.Ambient=Color3.fromRGB(205,205,205)
                Lighting.OutdoorAmbient=Color3.fromRGB(205,205,205)
            end)
        end
        if os.clock()>=nextESP then
            nextESP=os.clock()+.4
            local ok,count,distance=pcall(refreshESP)
            if ok and enabled.esp and not enabled.chop then
                if distance then
                    statusSet('ESP: '..count..' игроков • возможный убийца: '..math.floor(distance+.5)..' ст.')
                else
                    statusSet('ESP: '..count..' игроков • убийца не определён')
                end
            end
        end
    end
end)

statusSet('DeepWoods Hub v1.2: ESP, скорость, свет и рубка деревьев.')
