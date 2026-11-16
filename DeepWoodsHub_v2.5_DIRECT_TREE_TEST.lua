-- DeepWoods Hub v2.5 | DIRECT TREE TEST (experimental)
-- Observed during user manual chopping:
-- ReplicatedStorage.Remotes.ChopSwing:FireServer(Model:TreeTemplate)
-- Important: outgoing request was observed, but server acceptance of custom requests
-- has NOT been verified. No namecall hooks, no simulated GUI signals, no movement.
-- First REJOIN after running WoodRemoteProbe v1: the old namecall hook persists.

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')
local ENV = (getgenv and getgenv()) or _G

-- Stop previous hub routines so two independent farms never run together.
for _,k in ipairs({'DWH_Unload','DeepWoodsHub_Unload','DWH25_Stop'}) do
    if type(ENV[k])=='function' then pcall(ENV[k]) end
end
local previous = PG:FindFirstChild('DWH25_DirectTree')
if previous then pcall(function() previous:Destroy() end) end

local alive = true
local enabled = false
local testing = false
local compact = false
local radius = 10                 -- user requested 10 studs; character stays still
local interval = 0.48            -- conservative; game may enforce a server cooldown
local hitsPerTree = 6            -- avoid endlessly calling an unchanged model
local treeScanInterval = 3.0
local blacklistSeconds = 14
local lastScan = -100
local lastSend = -100
local target, targetHits = nil,0
local cooldown = setmetatable({}, {__mode='k'})
local trees = {}
local connections = {}
local sent, failed = 0,0
local gained = 0
local initialWood, currentWood = nil,nil
local statSource = 'не найден'
local lastWoodReading = -100
local remote = nil
local note = 'Не запускать вместе с прежним WoodProbe. После него перезайди в матч.'
local T = {
    bg=Color3.fromRGB(16,22,33), panel=Color3.fromRGB(26,34,51),
    item=Color3.fromRGB(40,52,72), accent=Color3.fromRGB(70,188,225),
    green=Color3.fromRGB(56,211,153), muted=Color3.fromRGB(172,191,207),
    text=Color3.fromRGB(236,246,251), red=Color3.fromRGB(252,110,127)
}
local function addConn(signal, callback)
    local c=signal:Connect(callback)
    connections[#connections+1]=c
    return c
end
local function make(kind,parent,props)
    local o=Instance.new(kind)
    for k,v in pairs(props or {}) do
        assert(type(k)=='string','Bad property '..tostring(k))
        o[k]=v
    end
    o.Parent=parent
    return o
end
local function round(o,r)
    make('UICorner',o,{CornerRadius=UDim.new(0,r or 8)})
end
local function ease(o,props)
    local ok=pcall(function()
        TweenService:Create(o,TweenInfo.new(.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props):Play()
    end)
    if not ok then for k,v in pairs(props) do o[k]=v end end
end

local gui=make('ScreenGui',PG,{
    Name='DWH25_DirectTree',IgnoreGuiInset=true,ResetOnSpawn=false,
    DisplayOrder=975,ZIndexBehavior=Enum.ZIndexBehavior.Sibling
})
local screenSize=(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(780,410)
local width=math.min(312,math.max(240,screenSize.X-20))
local height=228
local panel=make('Frame',gui,{
    Name='Panel',Active=true,BackgroundColor3=T.bg,BorderSizePixel=0,
    Size=UDim2.fromOffset(width,height),
    Position=UDim2.fromOffset(math.max(10,math.floor((screenSize.X-width)/2)),math.max(10,math.floor((screenSize.Y-height)/2)))
})
round(panel,13)
make('UIStroke',panel,{Color=T.accent,Thickness=1})
local title=make('TextLabel',panel,{
    Text='🌲 DeepWoods 2.5 · RPC',Font=Enum.Font.GothamBold,
    TextColor3=T.text,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,Position=UDim2.fromOffset(12,7),Size=UDim2.new(1,-65,0,25)
})
local minimize=make('TextButton',panel,{
    Text='−',Font=Enum.Font.GothamBold,TextColor3=T.text,TextSize=19,
    BackgroundColor3=T.item,BorderSizePixel=0,
    Position=UDim2.new(1,-34,0,6),Size=UDim2.fromOffset(27,27)
})
round(minimize,7)
local bubble=make('TextButton',gui,{
    Name='FloatingIcon',Text='🌲',Font=Enum.Font.GothamBold,TextSize=23,
    TextColor3=T.text,BackgroundColor3=T.panel,BorderSizePixel=0,
    Position=UDim2.fromOffset(12,math.floor((screenSize.Y-44)/2)),
    Size=UDim2.fromOffset(44,44),Visible=false,Active=true
})
round(bubble,12)
local function button(label,x,y,w,h)
    local b=make('TextButton',panel,{
        Text=label,Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=T.text,BackgroundColor3=T.item,BorderSizePixel=0,
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h)
    })
    round(b,8)
    return b
end
local totalWidth=width-22
local half=math.floor((totalWidth-8)/2)
local testButton=button('ТЕСТ 6 ЗАПРОСОВ',11,42,half,40)
local farmButton=button('AFK: ВЫКЛ',19+half,42,half,40)
local reportButton=button('ОТЧЁТ / КОПИЯ',11,90,totalWidth,33)
local stateLabel=make('TextLabel',panel,{
    Text='',Font=Enum.Font.GothamBold,TextSize=11,
    TextColor3=T.green,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,Position=UDim2.fromOffset(12,130),
    Size=UDim2.new(1,-24,0,36)
})
local infoLabel=make('TextLabel',panel,{
    Text=note,Font=Enum.Font.Gotham,TextSize=10,
    TextColor3=T.muted,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,BackgroundTransparency=1,
    Position=UDim2.fromOffset(12,168),Size=UDim2.new(1,-24,0,53)
})

local function display(message)
    note=tostring(message)
    if alive and infoLabel.Parent then infoLabel.Text=note end
end
local function onTap(btn,callback)
    -- One event only: Activated + MouseButton1Click double-toggled older menus.
    addConn(btn.Activated,function()
        if not alive then return end
        local ok,err=pcall(callback)
        if not ok then display('Ошибка: '..tostring(err):sub(1,130)) end
    end)
end
local function setSmall(small)
    compact=small
    local v=(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or screenSize
    if small then
        local x=math.clamp(bubble.Position.X.Offset,8,math.max(8,v.X-52))
        local y=math.clamp(bubble.Position.Y.Offset,16,math.max(16,v.Y-56))
        bubble.Position=UDim2.fromOffset(x,y)
        panel.Visible=false
        bubble.Visible=true
        ease(bubble,{BackgroundColor3=T.accent})
    else
        bubble.Visible=false
        local x=math.clamp(panel.Position.X.Offset,8,math.max(8,v.X-width-8))
        local y=math.clamp(panel.Position.Y.Offset,10,math.max(10,v.Y-height-10))
        panel.Position=UDim2.fromOffset(x,y)
        panel.Visible=true
        ease(panel,{BackgroundColor3=T.bg})
    end
end
onTap(minimize,function()setSmall(true)end)
onTap(bubble,function()setSmall(false)end)

local function characterRoot()
    local char=LP.Character
    local hum=char and char:FindFirstChildOfClass('Humanoid')
    local root=char and char:FindFirstChild('HumanoidRootPart')
    if not hum or hum.Health<=0 then return nil end
    return root
end
local function trunk(model)
    if not model or not model.Parent or not model:IsA('Model') then return nil end
    local pick,best=nil,-999
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA('BasePart') then
            local n=p.Name:lower()
            local score=0
            if n:find('trunk',1,true) or n:find('stem',1,true) or
               n:find('log',1,true) or n:find('ствол',1,true) then score=30 end
            if n:find('leaf',1,true) or n:find('branch',1,true) then score=-15 end
            if p.Transparency<.95 and p.Size.Magnitude>1.5 then score=score+5 end
            if score>best then pick,best=p,score end
        end
    end
    return pick
end
local function isTreeAlive(model)
    local p=trunk(model)
    if not p or p.Transparency>=.95 then return false end
    for _,key in ipairs({'Health','TreeHealth','WoodHealth','HP'}) do
        local v=model:GetAttribute(key)
        if type(v)=='number' and v<=0 then return false end
        local val=model:FindFirstChild(key)
        if val and (val:IsA('NumberValue') or val:IsA('IntValue')) and val.Value<=0 then return false end
    end
    return true
end
local function distanceTo(root,model)
    local p=trunk(model)
    if not p then return math.huge end
    local dx=p.Position.X-root.Position.X
    local dz=p.Position.Z-root.Position.Z
    return math.sqrt(dx*dx+dz*dz)
end
local function refreshTrees(force)
    if not force and os.clock()-lastScan<treeScanInterval then return end
    lastScan=os.clock()
    local root=characterRoot()
    trees={}
    if not root then return end
    -- Exact model name comes from the user's captured FireServer argument.
    for _,inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA('Model') and inst.Name=='TreeTemplate' then
            local d=distanceTo(root,inst)
            if d<=radius and isTreeAlive(inst) then
                trees[#trees+1]={model=inst,distance=d}
            end
        end
        if #trees>=70 then break end
    end
    table.sort(trees,function(a,b)return a.distance<b.distance end)
end
local function pickTree()
    local root=characterRoot()
    if not root then return nil end
    refreshTrees(false)
    local now=os.clock()
    for _,item in ipairs(trees) do
        local model=item.model
        if (cooldown[model] or 0)<=now and isTreeAlive(model) and distanceTo(root,model)<=radius then
            return model
        end
    end
    return nil
end

local WOOD_KEYS={'Wood','wood','WoodCount','WoodAmount','Woods','Древесина'}
local function woodReading()
    local nodes={LP,LP:FindFirstChild('leaderstats'),LP:FindFirstChild('Stats'),LP:FindFirstChild('Data')}
    for _,node in ipairs(nodes) do
        if node then
            for _,key in ipairs(WOOD_KEYS) do
                local ok,val=pcall(function()return node:GetAttribute(key)end)
                if ok and type(val)=='number' and val>=0 then
                    return val,'attribute:'..node.Name..'/'..key
                end
                local obj=node:FindFirstChild(key)
                if obj and (obj:IsA('IntValue') or obj:IsA('NumberValue')) then
                    return obj.Value,'value:'..node.Name..'/'..key
                end
            end
        end
    end
    return nil,'счётчик древесины недоступен'
end
local function observeWood()
    if os.clock()-lastWoodReading<.38 then return end
    lastWoodReading=os.clock()
    local value,source=woodReading()
    if value~=nil then
        if currentWood~=nil and value>currentWood then gained=gained+(value-currentWood) end
        currentWood=value
        if initialWood==nil then initialWood=value end
        statSource=source
    end
end
local function getRemote()
    if remote and remote.Parent then return remote end
    local folder=RS:FindFirstChild('Remotes')
    local r=folder and folder:FindFirstChild('ChopSwing')
    if r and r:IsA('RemoteEvent') then remote=r;return remote end
    return nil
end
local function fireTree(model)
    local r=getRemote()
    if not r then return false,'Нет ReplicatedStorage.Remotes.ChopSwing' end
    if not model or not model.Parent or not model:IsA('Model') then
        return false,'Нет Model:TreeTemplate'
    end
    local ok,err=pcall(function()r:FireServer(model)end)
    if ok then sent=sent+1 else failed=failed+1 end
    return ok,ok and 'RPC отправлен (не обязательно принят сервером)' or tostring(err)
end
local function resetTarget()
    target=nil
    targetHits=0
end
local function sendOne()
    observeWood()
    if not target or not isTreeAlive(target) or (cooldown[target] or 0)>os.clock() then
        resetTarget()
    end
    local root=characterRoot()
    if not root then return false,'Персонаж не готов' end
    if target and distanceTo(root,target)>radius then resetTarget() end
    if not target then
        target=pickTree()
        targetHits=0
    end
    if not target then return false,'Нет видимых TreeTemplate в радиусе '..radius..' ст.' end
    local before=currentWood
    local model=target
    local ok,why=fireTree(model)
    if ok then targetHits=targetHits+1 end
    observeWood()
    local progressed=before~=nil and currentWood~=nil and currentWood>before
    if progressed or not isTreeAlive(model) or targetHits>=hitsPerTree then
        cooldown[model]=os.clock()+(progressed and 3 or blacklistSeconds)
        resetTarget()
    end
    return ok,why
end
local function report()
    local available=(getRemote() and 'да' or 'нет')
    local count=#trees
    return 'DeepWoods RPC 2.5 | ChopSwing='..available..
        ' | TreeTemplate поблизости='..count..
        ' | RPC отправлено='..sent..' | ошибки='..failed..
        ' | Древесина +'..(currentWood~=nil and tostring(gained) or '?')..
        ' | источник='..statSource..
        ' | AFK='..(enabled and 'ВКЛ' or 'ВЫКЛ')
end
local function updateUi()
    if not alive then return end
    observeWood()
    if stateLabel.Parent then
        stateLabel.Text='RPC '..sent..'  ·  дерево +'..(currentWood~=nil and tostring(gained) or '?')..'  ·  целей '..#trees
    end
    farmButton.Text=enabled and 'AFK: ВКЛ' or 'AFK: ВЫКЛ'
    farmButton.BackgroundColor3=enabled and T.green or T.item
end
onTap(testButton,function()
    if testing then return end
    if enabled then display('Сначала выключи AFK, потом тест.') return end
    if not getRemote() then display('RemoteEvent ChopSwing не найден. Проверь режим игры.')return end
    testing=true
    testButton.Text='ТЕСТ ИДЁТ...'
    lastScan=-100
    refreshTrees(true)
    target=pickTree()
    targetHits=0
    if not target then
        testing=false
        testButton.Text='ТЕСТ 6 ЗАПРОСОВ'
        display('Не найден TreeTemplate в '..radius..' студиях. Встань рядом с деревом.')
        return
    end
    local model=target
    local before=currentWood
    local beforeSent=sent
    display('Отправляю до 6 вызовов ChopSwing к одному TreeTemplate...')
    task.spawn(function()
        for _=1,6 do
            if not alive then break end
            if not model.Parent then break end
            local ok,why=fireTree(model)
            if not ok then display(why) break end
            task.wait(.55)
        end
        task.wait(.55)
        observeWood()
        updateUi()
        local diff=(before~=nil and currentWood~=nil) and math.max(0,currentWood-before) or nil
        display('Тест завершён: RPC='..(sent-beforeSent)..
            ', древесина='..(diff and ('+'..diff) or 'неизвестно')..
            '. Если +0 и дерево не изменилось, сервер мог отклонить запрос.')
        resetTarget()
        testing=false
        testButton.Text='ТЕСТ 6 ЗАПРОСОВ'
    end)
end)
onTap(farmButton,function()
    if testing then display('Сначала заверши короткий тест.') return end
    if not enabled and not getRemote() then
        display('Не обнаружен ChopSwing. Войди в матч за фермера.')
        return
    end
    enabled=not enabled
    resetTarget()
    if enabled then lastScan=-100;refreshTrees(true) end
    updateUi()
    display(enabled and 'AFK: прямые RPC, без движения и фиксации камеры. Контролируй +древесины.' or 'AFK выключен')
end)
onTap(reportButton,function()
    updateUi()
    local msg=report()
    print('[DeepWoods v2.5] '..msg)
    if type(setclipboard)=='function' then
        pcall(function()setclipboard(msg)end)
        display('Отчёт скопирован. '..msg)
    else
        display(msg)
    end
end)

-- Start exactly one worker. No hooks or parallel request bursts.
task.spawn(function()
    local uiAt=0
    while alive do
        task.wait(.1)
        local now=os.clock()
        if enabled and not testing and now-lastSend>=interval then
            lastSend=now
            local ok,why=sendOne()
            if not ok and why then
                if now-lastScan>3.2 then display(why) end
            end
        end
        if now>=uiAt then
            uiAt=now+.48
            updateUi()
        end
    end
end)
local function stop()
    if not alive then return end
    enabled=false
    alive=false
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    pcall(function()gui:Destroy()end)
    if ENV.DWH25_Stop==stop then ENV.DWH25_Stop=nil end
end
ENV.DWH25_Stop=stop
print('[DeepWoods v2.5] Ready. Rejoin after WoodRemoteProbe v1 before testing!')
updateUi()
