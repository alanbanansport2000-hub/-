-- DeepWoods WOOD REMOTE PROBE v1 | diagnostics only
-- Does not activate trees, does not send remotes, does not modify camera or player.
-- Captures outgoing game RemoteEvent/RemoteFunction names during idle and real manual chops.
-- Requires a Delta-compatible hookmetamethod and getnamecallmethod. Roblox live test is necessary.
local Players = game:GetService('Players')
local PG = Players.LocalPlayer:WaitForChild('PlayerGui')
local UIS = game:GetService('UserInputService')
local ENV = (getgenv and getgenv()) or _G
local previous = PG:FindFirstChild('DWH_WoodProbe')
if previous then pcall(function() previous:Destroy() end) end
if type(ENV.DWH_WoodProbe_Stop)=='function' then pcall(ENV.DWH_WoodProbe_Stop) end

local active = true
local phase = 'off'
local events = {idle = {}, manual = {}}
local report = 'Проверка не запускалась'
local oldNamecall = nil
local hooked = false
local connections = {}
local copied = false
local function on(signal, f)
  local c=signal:Connect(f)
  connections[#connections+1]=c
  return c
end
local function new(class,parent,props)
  local x=Instance.new(class)
  for k,v in pairs(props or {}) do
    assert(type(k)=='string','Invalid GUI property')
    x[k]=v
  end
  x.Parent=parent
  return x
end
local function corner(x,r) new('UICorner',x,{CornerRadius=UDim.new(0,r or 8)}) end
local gui=new('ScreenGui',PG,{Name='DWH_WoodProbe',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=991})
local panel=new('Frame',gui,{Size=UDim2.fromOffset(302,188),Position=UDim2.fromOffset(14,85),BackgroundColor3=Color3.fromRGB(21,29,43),BorderSizePixel=0,Active=true})
corner(panel,12)
new('UIStroke',panel,{Color=Color3.fromRGB(76,151,196),Thickness=1.1})
local title=new('TextLabel',panel,{Text='🌲 Проверка реальной рубки',Font=Enum.Font.GothamBold,TextSize=14,TextColor3=Color3.fromRGB(235,245,255),TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-70,0,28),BackgroundTransparency=1})
local close=new('TextButton',panel,{Text='×',Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(250,251,255),BackgroundColor3=Color3.fromRGB(67,77,96),BorderSizePixel=0,Position=UDim2.new(1,-33,0,7),Size=UDim2.fromOffset(25,25)})
corner(close,7)
local msg=new('TextLabel',panel,{Text='Выключи AFK-хаб. Запусти проверку.\n5 секунд ничего не нажимай, затем 10 секунд\nруби деревья ВРУЧНУЮ.',Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(199,214,230),TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Position=UDim2.fromOffset(12,40),Size=UDim2.new(1,-24,0,74),BackgroundTransparency=1})
local start=new('TextButton',panel,{Text='НАЧАТЬ ЗАМЕР',Font=Enum.Font.GothamBold,TextColor3=Color3.fromRGB(15,23,33),TextSize=11,BackgroundColor3=Color3.fromRGB(86,198,237),BorderSizePixel=0,Position=UDim2.fromOffset(11,127),Size=UDim2.fromOffset(172,40)})
corner(start,8)
local copy=new('TextButton',panel,{Text='КОПИЯ',Font=Enum.Font.GothamBold,TextColor3=Color3.fromRGB(230,244,255),TextSize=11,BackgroundColor3=Color3.fromRGB(58,73,96),BorderSizePixel=0,Position=UDim2.fromOffset(191,127),Size=UDim2.fromOffset(100,40)})
corner(copy,8)

local function valueShape(v)
  local typ=typeof(v)
  if typ=='Instance' then
    local kind=v.ClassName
    if kind=='Player' or v:IsA('Player') then return 'Player' end
    return kind..':'..tostring(v.Name):sub(1,38)
  elseif typ=='Vector3' then
    return string.format('Vector3(%.0f,%.0f,%.0f)',v.X,v.Y,v.Z)
  elseif typ=='CFrame' then
    local p=v.Position
    return string.format('CFrame(%.0f,%.0f,%.0f)',p.X,p.Y,p.Z)
  elseif typ=='number' then
    return string.format('num:%.2f',v)
  elseif typ=='boolean' then
    return 'bool:'..tostring(v)
  elseif typ=='string' then
    local s=v:lower()
    if s:find('tree',1,true) or s:find('wood',1,true) or s:find('chop',1,true)
       or s:find('swing',1,true) or s:find('axe',1,true) then
      return 'string:'..v:sub(1,38)
    end
    return 'string(len='..#v..')'
  end
  return typ
end
local function capture(self,method,args)
  local bucket=events[phase]
  if not bucket then return end
  if not (self:IsA('RemoteEvent') or self:IsA('RemoteFunction') or self:IsA('UnreliableRemoteEvent')) then return end
  local fullname=self:GetFullName()
  local key=method..' | '..fullname
  local item=bucket[key]
  if not item then
    item={count=0,shape='',related=false}
    bucket[key]=item
  end
  item.count=item.count+1
  if item.count==1 then
    local parts={}
    for i=1,math.min(args.n,5) do
      parts[i]=valueShape(args[i])
    end
    item.shape=table.concat(parts,', ')
    local low=(key..' '..item.shape):lower()
    item.related=(low:find('tree',1,true)~=nil or low:find('wood',1,true)~=nil or low:find('chop',1,true)~=nil or low:find('swing',1,true)~=nil)
  end
end
local function tryHook()
  if hooked then return true end
  if type(hookmetamethod)~='function' or type(getnamecallmethod)~='function' then
    return false,'Delta не предоставляет hookmetamethod/getnamecallmethod'
  end
  local function wrapper(self,...)
    if active and (phase=='idle' or phase=='manual') then
      local ok,m=pcall(getnamecallmethod)
      if ok and (m=='FireServer' or m=='InvokeServer') then
        local originExecutor=false
        if type(checkcaller)=='function' then
          local got,flag=pcall(checkcaller)
          if got then originExecutor=flag end
        end
        if not originExecutor then
          local args=table.pack(...)
          pcall(capture,self,m,args)
        end
      end
    end
    return oldNamecall(self,...)
  end
  local closed=wrapper
  if type(newcclosure)=='function' then
    local ok,res=pcall(newcclosure,wrapper)
    if ok then closed=res end
  end
  local ok,prev=pcall(function()return hookmetamethod(game,'__namecall',closed)end)
  if not ok or type(prev)~='function' then return false,tostring(prev) end
  oldNamecall=prev
  hooked=true
  return true
end
local function render()
  local sorted={}
  for name,data in pairs(events.manual) do
    local base=events.idle[name]
    local idleCount=base and base.count or 0
    table.insert(sorted,{name=name,total=data.count,idle=idleCount,shape=data.shape,related=data.related})
  end
  table.sort(sorted,function(a,b)
    if a.related~=b.related then return a.related end
    return (a.total-a.idle*2)>(b.total-b.idle*2)
  end)
  local out={'DeepWoods WoodProbe v1','5s без ударов, 10s ручной рубки','Вручную зафиксировано RPC: '..#sorted}
  if #sorted==0 then
    out[#out+1]='Нет вызовов FireServer/InvokeServer (или executor hook не увидел их).'
  end
  for i=1,math.min(#sorted,15) do
    local s=sorted[i]
    out[#out+1]=string.format('%d. [%s] manual=%d, idle=%d | %s | (%s)',i,s.related and 'WOOD?' or 'other',s.total,s.idle,s.name,s.shape)
  end
  report=table.concat(out,'\n')
  return report
end
local runningProbe=false
on(start.Activated,function()
  if runningProbe then return end
  local ok,why=tryHook()
  if not ok then
    msg.Text='Не удалось подключить перехват:\n'..tostring(why):sub(1,160)
    return
  end
  runningProbe=true
  start.Text='ИДЁТ ЗАМЕР...'
  events={idle={},manual={}}
  task.spawn(function()
    phase='idle'
    for n=5,1,-1 do
      if not active then return end
      msg.Text='Этап 1/2: ничего не нажимай. '..n..' с.\nНе запускай другие скрипты во время теста.'
      task.wait(1)
    end
    if not active then return end
    phase='manual'
    for n=10,1,-1 do
      if not active then return end
      msg.Text='Этап 2/2: руби дерево ВРУЧНУЮ! '..n..' с.\nПодойди вплотную и нажимай обычный Swing.'
      task.wait(1)
    end
    phase='off'
    if not active then return end
    local summary=render()
    print('[DeepWoods WoodProbe] '..summary)
    copied=false
    if type(setclipboard)=='function' then
      local clipboardOK=pcall(function()setclipboard(summary)end)
      copied=clipboardOK
    end
    msg.Text='Готово. Вызовов: '..tostring(#(function()
       local t={};for k in pairs(events.manual) do t[#t+1]=k end;return t
      end)())..'.\n'..(copied and 'Отчёт скопирован. Пришли текст в чат.' or 'Нажми «КОПИЯ» или открой консоль Delta.')
    runningProbe=false
    start.Text='ПОВТОРИТЬ'
  end)
end)
on(copy.Activated,function()
  local result=report
  if type(setclipboard)=='function' then
    local ok=pcall(function()setclipboard(result)end)
    msg.Text=ok and 'Отчёт скопирован в буфер обмена.' or 'Не получилось копировать; посмотри консоль Delta.'
  else
    msg.Text='Нет setclipboard. Смотри консоль Delta (print).'
  end
  print('[DeepWoods WoodProbe] '..result)
end)
local function stop()
  active=false
  phase='off'
  for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
  pcall(function() gui:Destroy() end)
  if ENV.DWH_WoodProbe_Stop==stop then ENV.DWH_WoodProbe_Stop=nil end
  -- Hook stays as a transparent pass-through; a game rejoin fully removes it.
end
ENV.DWH_WoodProbe_Stop=stop
on(close.Activated,stop)
print('[DeepWoods WoodProbe] Ready. Disable other auto-farm before measuring.')
