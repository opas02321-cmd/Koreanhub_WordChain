-- KoreanHub: Korean Dodgeball / 한국 피구
-- Build 9 (5119 log): retain acknowledged input routes, measure character motion, recheck short reservations, and verify click-based throw charging.
-- Previous build: throttled discovery, cached button/cooldown lookups, optional manual perfect-window assistance.
-- Previous build: preserve bounded VFX tracking; fix mesh classification, premature fallback and unacknowledged catch inputs.
-- Previous build: mobile input handlers, automatic ball indexing, bounded scanning and reversible performance controls.
-- No guessed game remotes are invoked. Input transport is reported as an attempt, not verified server success.
-- Percentage controls attempts at the yellow interval, not the server's success probability.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local Run=game:GetService('RunService')
local GS=game:GetService('GuiService')
local PG=Players.LocalPlayer:WaitForChild('PlayerGui')
local player=Players.LocalPlayer
local env=getgenv and getgenv() or _G
if env.KoreanDodgeCleanup then pcall(env.KoreanDodgeCleanup) end
local alive=true
local links={}
local function bind(signal,fn) local c=signal:Connect(fn);links[#links+1]=c;return c end
local settings={Catch=true,CatchRescue=true,ManualAssist=false,Dodge=false,Start=false,Perfect=100,Throw=false,ThrowInput='자동',ThrowDelay=0.5,ThrowPerfect=100,ThrowLead=0,ThrowMaxHold=1.5,Fallback=true,FallbackTime=0.10,Lead=0,DodgeTime=0.20,StartSeconds=8}
local Rayfield=loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local window=Rayfield:CreateWindow({Name='KoreanHub · 한국 피구',LoadingTitle='한국 피구',LoadingSubtitle='잡기 · 피하기 · 던지기 · 시작 공',ConfigurationSaving={Enabled=false},KeySystem=false})
local tab=window:CreateTab('피구',4483362458)
local throwTab=window:CreateTab('던지기',4483362458)
local info=window:CreateTab('감지 / 진단',4483362458)
local perfTab=window:CreateTab('FPS / 최적화',4483362458)
local status=tab:CreateParagraph({Title='상태',Content='기능을 켜면 게임의 버튼과 판정 게이지를 찾습니다.'})
local detail=info:CreateParagraph({Title='감지 결과',Content='스캔 중'})
local lastMessage='준비'
local function say(s) lastMessage=s end
local function paragraph(o,title,s) pcall(function() o:Set({Title=title,Content=s}) end) end
local function norm(s) return tostring(s or ''):gsub('<[^>]->',''):gsub('%s+',''):lower() end
local ownRoots={}
for _,o in ipairs(PG:GetDescendants()) do
 if (o:IsA('TextLabel') or o:IsA('TextButton')) and o.Text=='KoreanHub · 한국 피구' then
  local root=o:FindFirstAncestorOfClass('ScreenGui');if root then ownRoots[root]=true end
 end
end
local function excluded(o)
 local p=o
 while p and p~=game do
  if ownRoots[p] or p.Name:lower():find('rayfield',1,true) then return true end
  p=p.Parent
 end
 return false
end
local function visible(o)
 if not o or not o.Parent or excluded(o) then return false end
 local p=o
 while p and p~=game do
  if p:IsA('GuiObject') and not p.Visible then return false end
  if p:IsA('LayerCollector') and not p.Enabled then return false end
  p=p.Parent
 end
 return true
end
local gui,parts={},{}
local uiDirty=true
local practiceFeedback={Count=0,Last=nil,Best=nil,Minimum=nil}
local feedbackSeen=setmetatable({},{__mode='k'})
local function parsePracticeAccuracy(text)
 local compact=norm(text):gsub('：',':')
 local n=tonumber(compact:match('정확도:?(%d+%.?%d*)%%'))
 return n and n>=0 and n<=100 and n or nil
end
local function watchPracticeFeedback(o)
 local value=parsePracticeAccuracy(o.Text)
 if not value or feedbackSeen[o] then return end
 local function read()
  local text=o.Text
  if feedbackSeen[o]==text then return end
  feedbackSeen[o]=text
  local accuracy=parsePracticeAccuracy(text)
  if not accuracy then return end
  practiceFeedback.Count=practiceFeedback.Count+1;practiceFeedback.Last=accuracy
  practiceFeedback.Best=math.max(practiceFeedback.Best or accuracy,accuracy)
  practiceFeedback.Minimum=math.min(practiceFeedback.Minimum or accuracy,accuracy)
 end
 feedbackSeen[o]=true;read()
 bind(o:GetPropertyChangedSignal('Text'),read)
end
local aliases={catch={'잡기','캐치','catch'},dodge={'피하기','회피','dodge'},dash={'대시','대쉬','dash'},throw={'던지기','투척','throw'},join={'게임참가하기','게임참여하기'}}
local actionKeys={catch='e',throw='e',dodge='q',dash='f'}
local function actionOf(text)
 text=norm(text)
 for action,words in pairs(aliases) do
  for _,word in ipairs(words) do
   if text==word then return action end
   if actionKeys[action] and text:sub(1,#word)==word then
    local suffix=text:sub(#word+1):gsub('[%[%]%(%){}]','')
    if suffix==actionKeys[action] then return action end
   end
  end
 end
end
local allParts={}
local onBallRecognized=nil
local function registerBall(o)
 if parts[o] then return end
 parts[o]=true
 if onBallRecognized then onBallRecognized(o) end
end
local function sizeInBallRange(size)
 local big=math.max(size.X,size.Y,size.Z);local small=math.min(size.X,size.Y,size.Z)
 return small>=0.2 and big<=25 and big/small<=2.8
end
local function partCandidate(o)
 if not o:IsA('BasePart') then return false end
 if not sizeInBallRange(o.Size) then return false end
 local p=o;local named=false
 for _=1,4 do
  if not p or p==workspace then break end
  local name=p.Name:lower()
  if name:find('shadow',1,true) or name:find('preview',1,true) then return false end
  if name:find('ball',1,true) or name:find('피구공',1,true) or name=='공' then named=true end
  p=p.Parent
 end
 local sphere=o:IsA('Part') and o.Shape==Enum.PartType.Ball
 local mesh=o:FindFirstChildOfClass('SpecialMesh')
 if mesh and o.Color.R>0.75 and o.Color.G<0.4 then sphere=true end
 -- Mesh balls often use a neutral part name inside a named ball Model.
 if named or sphere then return true end
 if o:IsA('MeshPart') and o.Color.R>0.75 and o.Color.G<0.4 then
  local size=o.Size
  return math.max(size.X,size.Y,size.Z)/math.min(size.X,size.Y,size.Z)<1.6
 end
 return false
end
local function track(o,late)
 if (o:IsA('TextLabel') or o:IsA('TextButton') or o:IsA('Frame') or o:IsA('ImageLabel') or o:IsA('ImageButton')) and not excluded(o) then gui[o]=true;uiDirty=true end
 if o:IsA('BasePart') then
  allParts[o]=true
  local candidate=partCandidate(o)
  if candidate then registerBall(o) end
  -- DescendantAdded can run before the server assigns the name/shape/parent. Only size-plausible
  -- parts are worth a late re-check; everything else (VFX debris, trail fragments) is skipped so
  -- the game's own effect churn does not pile up delayed closures.
  if late and not candidate and sizeInBallRange(o.Size) then for _,delay in ipairs({0.15,1}) do task.delay(delay,function()
   if alive and o.Parent and partCandidate(o) then registerBall(o) end
  end) end end
 end
end
for _,o in ipairs(PG:GetDescendants()) do track(o) end
bind(PG.DescendantAdded,track)
task.spawn(function()
 local n=0
 for _,o in ipairs(workspace:GetDescendants()) do
  if not alive then return end
  if o:IsA('BasePart') or ((o:IsA('GuiObject')) and (o:FindFirstAncestorOfClass('BillboardGui') or o:FindFirstAncestorOfClass('SurfaceGui'))) then track(o) end
  n=n+1;if n%500==0 then task.wait() end
 end
end)
bind(workspace.DescendantAdded,function(o)
 if o:IsA('BasePart') or (o:IsA('GuiObject') and (o:FindFirstAncestorOfClass('BillboardGui') or o:FindFirstAncestorOfClass('SurfaceGui'))) then track(o,true) end
end)
local function character()
 local c=player.Character
 return c,c and c:FindFirstChild('HumanoidRootPart'),c and c:FindFirstChildOfClass('Humanoid')
end
local function connections(event)
 if not event or type(getconnections)~='function' then return {} end
 local ok,list=pcall(getconnections,event)
 return ok and type(list)=='table' and list or {}
end
local function connected(o,event)
 local ok,value=pcall(function()return o[event]end)
 return ok and #connections(value)>0
end
local buttonCache=setmetatable({},{__mode='k'})
local function guiButton(o)
 local cached=buttonCache[o]
 if cached and cached.Parent and (cached==o or o:IsDescendantOf(cached)) then return cached end
 local p=o;local best=nil;local bestScore=-1
 for depth=1,7 do
  if not p or not p:IsA('GuiObject') then break end
  local score=-1
  if p:IsA('GuiButton') then
   score=20
   if connected(p,'Activated') or connected(p,'MouseButton1Click') then score=100
   elseif connected(p,'InputBegan') or connected(p,'MouseButton1Down') then score=90 end
  elseif connected(p,'InputBegan') or connected(p,'InputEnded') then score=70 end
  score=score-depth
  if score>bestScore then best=p;bestScore=score end
  p=p.Parent
 end
 if best then buttonCache[o]=best end
 return best
end
local actions={}
local actionLabels={}
local actionError=''
local actionTransport='미확인'
local inputMode='자동'
local cooldownCache=setmetatable({},{__mode='k'})
local cooldownLists=setmetatable({},{__mode='k'})
local cooldownWatched=setmetatable({},{__mode='k'})
local function cooldown(button)
 local now=os.clock();local cached=cooldownCache[button]
 if cached and now-cached.At<0.12 then return cached.Value end
 local value=false
 local labels=cooldownLists[button]
 if not labels then
  labels=button:GetDescendants();labels[#labels+1]=button;cooldownLists[button]=labels
  if not cooldownWatched[button] then
   cooldownWatched[button]=true
   bind(button.DescendantAdded,function()cooldownLists[button]=nil;cooldownCache[button]=nil end)
  end
 end
 for _,o in ipairs(labels) do
  if (o:IsA('TextLabel') or o:IsA('TextButton')) and visible(o) then
   local s=norm(o.Text)
   if s:match('^%d+%.?%d*$') and tonumber(s)>0 then value=true;break end
  end
 end
 cooldownCache[button]={At=now,Value=value}
 return value
end
local function actionVisible(action)
 local button=actions[action];local label=actionLabels[action]
 return button and visible(button) and (not label or (visible(label) and actionOf(label.Text)==action)) or false
end
local function actionReady(action)
 local button=actions[action]
 -- Some mobile controls have Active=false but handle InputBegan themselves.
 if not actionVisible(action) or cooldown(button) then return false end
 local ok,value=pcall(function()return button.Interactable end)
 return not ok or value~=false
end
local VIM=nil
pcall(function()VIM=game:GetService('VirtualInputManager')end)
local function fireList(list,...)
 local worked=false
 for _,c in ipairs(list) do
  if c.Enabled~=false then
   local ok,err=false,nil
   if type(c.Fire)=='function' then ok,err=pcall(c.Fire,c,...)
   elseif type(c.Function)=='function' then ok,err=pcall(c.Function,...) end
   if err then actionError=tostring(err) end
   worked=ok or worked
  end
 end
 return worked
end
local function signalFor(o,name)
 local ok,value=pcall(function()return o[name]end)
 return ok and value or nil
end
local function centerOf(button)
 local center=button.AbsolutePosition+button.AbsoluteSize/2
 local root=button:FindFirstAncestorOfClass('ScreenGui')
 if root and not root.IgnoreGuiInset then center=center+GS:GetGuiInset() end
 return center
end
local function localSignal()
 local list={}
 local signal={}
 function signal:Connect(fn)
  local c={Connected=true};function c:Disconnect()self.Connected=false end
  list[#list+1]={C=c,F=fn};return c
 end
 function signal:Fire(...)for _,entry in ipairs(list) do if entry.C.Connected then pcall(entry.F,...) end end end
 return signal
end
local function beginButton(button,held,route)
 local mode=route or inputMode
 local center=centerOf(button)
 local function touchCallbacks()
  local downs=connections(signalFor(button,'InputBegan'))
  local ups=connections(signalFor(button,'InputEnded'))
  if #downs+#ups==0 or (held and #downs==0) then return nil end
  local changed=localSignal();local stateChanged=localSignal()
  local input={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.Begin,
   Position=Vector3.new(center.X,center.Y,0),Delta=Vector3.new(0,0,0),Changed=changed}
  function input:GetPropertyChangedSignal(name)return name=='UserInputState' and stateChanged or changed end
  local before={};for _,c in ipairs(connections(UIS.InputEnded)) do before[c]=true end
  if #downs>0 and not fireList(downs,input,false) then return nil end
  -- Some games connect a one-shot global release listener inside InputBegan.
  -- Release only listeners installed by this press, never unrelated global inputs.
  local newUps={};for _,c in ipairs(connections(UIS.InputEnded)) do if not before[c] then newUps[#newUps+1]=c end end
  actionTransport='터치 콜백 입력 시도'
  return {Button=button,Release=function()
   input.UserInputState=Enum.UserInputState.End
   changed:Fire('UserInputState');stateChanged:Fire()
   local a=fireList(ups,input,false);local b=fireList(newUps,input,false)
   return a or b or #ups+#newUps==0
  end}
 end
 local function mouseCallbacks()
  local downs=connections(signalFor(button,'MouseButton1Down'))
  local ups=connections(signalFor(button,'MouseButton1Up'))
  if #downs==0 or (held and #ups==0) then return nil end
  if not fireList(downs,center.X,center.Y) then return nil end
  actionTransport='마우스 누르기/놓기 콜백 시도'
  return {Button=button,Release=function()return #ups==0 or fireList(ups,center.X,center.Y)end}
 end
 local function virtualMouse()
  if not VIM then return nil end
  local ok,err=pcall(function()VIM:SendMouseButtonEvent(center.X,center.Y,0,true,game,0)end)
  if not ok then actionError=tostring(err);return nil end
  actionTransport='가상 화면 입력 시도'
  return {Button=button,Release=function()return pcall(function()VIM:SendMouseButtonEvent(center.X,center.Y,0,false,game,0)end)end}
 end
 local function clickCallbacks()
  if held then return nil end
  local input={UserInputType=Enum.UserInputType.Touch,UserInputState=Enum.UserInputState.End,Position=Vector3.new(center.X,center.Y,0)}
  for _,name in ipairs({'Activated','MouseButton1Click'}) do
   local list=connections(signalFor(button,name))
   if #list>0 and fireList(list,input,1) then
    actionTransport=name..' 콜백 입력 시도'
    return {Button=button,Release=function()return true end}
   end
  end
 end
 if mode=='터치 콜백' then return touchCallbacks() end
 if mode=='마우스 콜백' then return mouseCallbacks() end
 if mode=='가상 마우스' then return virtualMouse() end
 if mode=='버튼 클릭' then return clickCallbacks() end
 local token=touchCallbacks() or mouseCallbacks() or clickCallbacks()
 if token then return token end
 return virtualMouse()
end
local activePresses={}
local function ownPress(token)
 if not token then return nil end
 local release=token.Release;local released=false
 activePresses[token]=true
 token.Release=function()
  if released then return true end
  released=true;activePresses[token]=nil
  return release()
 end
 return token
end
local function invoke(action,route)
 if not actionReady(action) then return false end
 local token=ownPress(beginButton(actions[action],false,route))
 if token then
  -- Release on the next scheduler slice so press/release cannot collapse into one input frame.
  task.delay(0.025,function()local ok,result=pcall(token.Release);if not ok or result==false then actionError='버튼 놓기 실패' end end)
  return true
 end
 actionError='버튼은 감지했지만 이 환경에서 사용할 입력 처리기가 없습니다.'
 say('자동 입력 실패 · 감지 / 진단 확인');return false
end
-- Pure timing/trajectory helpers; exposed only in local tests, not as game state edits.
local function choosePerfect(percent,roll) return roll<math.clamp(percent,0,100)/100 end
local function bandHit(previous,current,low,high)
 if not current or not low or not high then return false end
 if current>=low and current<=high then return true end
 if previous then return math.min(previous,current)<=high and math.max(previous,current)>=low end
 return false
end
local function normalBand(green,yellow)
 if not green then return nil end
 local a,b=green[1],green[2]
 if yellow and yellow[1]<b and yellow[2]>a then
  local left={a,math.min(b,yellow[1])};local right={math.max(a,yellow[2]),b}
  if left[2]-left[1]>right[2]-right[1] then a,b=left[1],left[2] else a,b=right[1],right[2] end
 end
 if b-a<2 then return nil end
 local margin=(b-a)*0.20
 return {a+margin,b-margin}
end
local function closestApproach(relativePosition,relativeVelocity,radius,horizon)
 local speed2=relativeVelocity:Dot(relativeVelocity)
 if speed2<1 then return nil end
 local t=-relativePosition:Dot(relativeVelocity)/speed2
 if t<0 or t>horizon then return nil end
 local miss=(relativePosition+relativeVelocity*t).Magnitude
 if miss>radius then return nil end
 return t,miss
end
local function color(o)
 if o:IsA('Frame') and o.BackgroundTransparency<0.5 then return o.BackgroundColor3 end
 if (o:IsA('ImageLabel') or o:IsA('ImageButton')) and o.ImageTransparency<0.5 then return o.ImageColor3 end
end
local function isYellow(c) return c and c.R>0.72 and c.G>0.62 and c.B<0.5 end
local function isWhite(c) return c and c.R>0.78 and c.G>0.78 and c.B>0.78 end
local function isGreen(c) return c and c.G>0.55 and c.G>c.R*1.20 and c.G>c.B*1.20 end
local gauges=nil
local onCatchGaugeChanged=nil
local catchConnections={}
local function setCatchGauge(value)
 local same=gauges and value and gauges.Root==value.Root and gauges.Marker==value.Marker and gauges.Yellow==value.Yellow
 gauges=value
 if same then return end
 for _,c in ipairs(catchConnections) do c:Disconnect() end
 catchConnections={}
 if not value then return end
 -- Catch a position update even when it occurs between two render callbacks.
 for _,entry in ipairs({{value.Marker,'AbsolutePosition'},{value.Marker,'AbsoluteSize'},{value.Yellow,'AbsolutePosition'}}) do
  catchConnections[#catchConnections+1]=bind(entry[1]:GetPropertyChangedSignal(entry[2]),function()
   if alive and onCatchGaugeChanged then
    local ok,err=pcall(onCatchGaugeChanged)
    if not ok then actionError='잡기 감지 오류: '..tostring(err) end
   end
  end)
 end
end
local chargeGauge=nil
local chargeConnection=nil
local onChargeChanged=nil
local function chargeNumber(text)
 local n=tonumber(norm(text):match('^(%d+%.?%d*)%%$'))
 if n and n>=0 and n<=100 then return n end
end
local function setChargeGauge(value)
 if chargeGauge and value and chargeGauge.Percent==value.Percent then chargeGauge=value;return end
 if chargeConnection then chargeConnection:Disconnect();chargeConnection=nil end
 chargeGauge=value
 if value then
  chargeConnection=bind(value.Percent:GetPropertyChangedSignal('Text'),function()
   if alive and onChargeChanged then
    local ok,err=pcall(onChargeChanged);if not ok then actionError='충전 감지 오류: '..tostring(err) end
   end
  end)
 end
end
local guiScanTime=0
local ballScanCursor=nil
local markerHistory={}
local function localGauge(o)
 local layer=o:FindFirstAncestorOfClass('BillboardGui') or o:FindFirstAncestorOfClass('SurfaceGui')
 if layer then
  local c=player.Character
  local adornee=layer.Adornee or layer.Parent
  return c and adornee and (adornee==c or adornee:IsDescendantOf(c)) or false
 end
 return o:IsDescendantOf(PG)
end
local function scanUI()
 local found={};local foundLabels={};local scores={};local yellows={};local percents={};local perfectTags={}
 local timer=nil;local starting=false
 for o in pairs(gui) do
  if not o.Parent then gui[o]=nil
  elseif visible(o) then
   if o:IsA('TextLabel') or o:IsA('TextButton') then
    watchPracticeFeedback(o)
    local text=norm(o.Text);local action=actionOf(text)
    if localGauge(o) then
     if chargeNumber(text) then percents[#percents+1]=o end
     if text=='perfect' or text=='퍼펙트' then perfectTags[#perfectTags+1]=o end
    end
    if action then
     local button=guiButton(o)
     if button and visible(button) and button:IsDescendantOf(PG) then
      local center=button.AbsolutePosition+button.AbsoluteSize/2
      local q=center.X
      if q>(scores[action] or -math.huge) then found[action]=button;foundLabels[action]=o;scores[action]=q end
     end
    end
    if o:IsDescendantOf(PG) and o.AbsolutePosition.Y<math.max(240,((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or 720)*0.34) then
     local m,s=text:match('^(%d+):(%d%d)$')
     if m then timer=tonumber(m)*60+tonumber(s) end
     if text=='경기시작' or text=='게임시작' or text=='시작!' or text=='go!' then starting=true end
    end
   end
   if localGauge(o) and isYellow(color(o)) and o.AbsoluteSize.Y>1 and o.AbsoluteSize.Y<35 and o.AbsoluteSize.X>=6 and o.AbsoluteSize.X<150 then yellows[#yellows+1]=o end
  end
 end
 for action,button in pairs(actions) do
  if not found[action] and button.Parent then found[action]=button;foundLabels[action]=actionLabels[action] end
 end
 actions=found;actionLabels=foundLabels
 -- 5099.mp4: throw UI is a filling bar, a nearby PERFECT tag and a 0..100% label.
 -- It has no moving white cursor. Pair only nearby local gauge labels, not HUD percentages.
 local charge,bestCharge=nil,math.huge
 for _,percent in ipairs(percents) do
  local pp=percent.AbsolutePosition+percent.AbsoluteSize/2
  for _,tag in ipairs(perfectTags) do
   local tp=tag.AbsolutePosition+tag.AbsoluteSize/2
   local dx=math.abs(pp.X-tp.X);local dy=pp.Y-tp.Y
   if dx<160 and dy>40 and dy<650 then
    local q=dx+dy*0.1
    if q<bestCharge then charge={Percent=percent,Perfect=tag};bestCharge=q end
   end
  end
 end
 -- Some versions draw PERFECT as an image. Fall back to a narrow local bar
 -- directly above the numeric charge label, rather than requiring text in the image.
 if not charge then
  for _,percent in ipairs(percents) do
   local pp=percent.AbsolutePosition+percent.AbsoluteSize/2
   for o in pairs(gui) do
    if o:IsA('Frame') and visible(o) and localGauge(o) then
     local size=o.AbsoluteSize;local pos=o.AbsolutePosition
     local gap=pp.Y-(pos.Y+size.Y);local dx=math.abs(pp.X-(pos.X+size.X/2))
     if size.X>=6 and size.X<=80 and size.Y>=60 and size.Y<=650 and size.Y>size.X*3
      and gap>=-5 and gap<=65 and dx<=math.max(20,size.X) then
      local q=dx+math.abs(gap)*0.2
      if q<bestCharge then charge={Percent=percent,Root=o};bestCharge=q end
     end
    end
   end
  end
 end
 if not charge and chargeGauge and chargeGauge.Percent.Parent then charge=chargeGauge end
 setChargeGauge(charge)
 -- Reclassify a bounded batch; this also catches late name/color/shape changes.
 for _=1,48 do
  local o=next(allParts,ballScanCursor);ballScanCursor=o
  if not o then break end
  if o.Parent then
   if partCandidate(o) then registerBall(o) end
  else allParts[o]=nil;parts[o]=nil;ballScanCursor=nil end
 end
 local selected=nil;local best=-math.huge
 for _,yellow in ipairs(yellows) do
  local parent=yellow.Parent
  for depth=1,5 do
   if not parent or not parent:IsA('GuiObject') then break end
   local size=parent.AbsoluteSize
   if size.Y>=60 and size.Y<=650 and size.Y>size.X*2.4 and size.X<160 then
    local marker,green=nil,nil;local mq=-math.huge
    for _,o in ipairs(parent:GetDescendants()) do
     if o:IsA('GuiObject') and visible(o) then
      local c=color(o);local s=o.AbsoluteSize
      local x=o.AbsolutePosition.X+s.X/2
      local yx=yellow.AbsolutePosition.X+yellow.AbsoluteSize.X/2
      if isWhite(c) and s.X>=s.Y*1.5 and s.Y<=size.Y*0.12 and s.Y>=1 and math.abs(x-yx)<math.max(20,size.X) then
       local q=s.X/s.Y
       local name=o.Name:lower()
       if name:find('marker',1,true) or name:find('cursor',1,true) or name:find('indicator',1,true) then q=q+50 end
       local y=o.AbsolutePosition.Y+s.Y/2
       if markerHistory[o] and math.abs(markerHistory[o]-y)>1 then q=q+100 end
       markerHistory[o]=y
       if q>mq then marker=o;mq=q end
      end
      if isGreen(c) and s.Y>yellow.AbsoluteSize.Y*2 and s.X>yellow.AbsoluteSize.X*0.5 then green=o end
     end
    end
    if marker then
     local q=100-depth*5
     if parent:IsDescendantOf(PG) then q=q+5 end
     if q>best then selected={Root=parent,Yellow=yellow,Marker=marker,Green=green};best=q end
     break
    end
   end
   parent=parent.Parent
  end
 end
 if not selected and gauges and gauges.Root.Parent and gauges.Marker.Parent and gauges.Yellow.Parent then selected=gauges end
 setCatchGauge(selected);guiScanTime=os.clock()
 return {Timer=timer,Starting=starting,Lobby=actionVisible('join')}
end
local manualBall=nil
local motion={}
local lastCatch,lastDodge=-math.huge,-math.huge
local cue={On=false,LastSeen=-math.huge,Perfect=true,Caught=false,Dodged=false,Previous=nil,Predicted=nil,At=nil,Root=nil}
local catchSchedule=nil
local function resetCue()
 catchSchedule=nil
 cue.On=false;cue.Caught=false;cue.Dodged=false;cue.Previous=nil;cue.Predicted=nil;cue.At=nil;cue.Root=nil
 cue.MarkerY=nil;cue.MarkerAt=nil;cue.MarkerSpeed=nil;cue.SampleRoot=nil
 cue.Pending=nil;cue.Attempts=0;cue.CooldownSeen=false;cue.TimerCount=0
end
local start={Until=0,Done=false,Manual=false,Ball=nil,Dash=false,Moving=false,MoveAt=0,LastCatch=-math.huge,PreviousTimer=nil,Lobby=nil,StartShown=false}
local function armStart(manual)
 start.Manual=manual==true
 start.Until=os.clock()+settings.StartSeconds;start.Done=false;start.Ball=nil;start.Dash=false;start.Moving=false;start.MoveAt=0;start.LastCatch=-math.huge
 say('시작 공 탐색 중')
end
local function heldPart(o)
 local p=o.Parent
 while p and p~=workspace do
  if p:IsA('Model') and p:FindFirstChildOfClass('Humanoid') then return true end
  p=p.Parent
 end
 return false
end
local rootMotion={}
local function observedRootVelocity(root,now)
 local velocity=root.AssemblyLinearVelocity
 local elapsed=rootMotion.At and now-rootMotion.At or 0
 if rootMotion.Root==root and elapsed>0 and elapsed<0.25 then
  local observed=(root.Position-rootMotion.Position)/elapsed
  -- Reject spawn/teleport discontinuities rather than interpreting them as a dodge.
  if observed.Magnitude>1 and observed.Magnitude<250 and (observed-velocity).Magnitude>5 then velocity=observed end
 end
 rootMotion.Root=root;rootMotion.Position=root.Position;rootMotion.At=now
 return velocity
end
local function getBalls(root,dt)
 local ownVelocity=observedRootVelocity(root,os.clock())
 local threat,threatTime=nil,math.huge
 local neutral,neutralDistance=nil,math.huge
 local characterModel=player.Character
 if manualBall and manualBall.Parent then parts[manualBall]=true end
 for part in pairs(parts) do
  if not part.Parent then parts[part]=nil;motion[part]=nil
  elseif (characterModel and part:IsDescendantOf(characterModel)) or heldPart(part) then motion[part]=nil
  else
   local position=part.Position;local previous=motion[part]
   local velocity=part.AssemblyLinearVelocity
   if previous and dt>0 and dt<0.3 then
    local observed=(position-previous)/dt
    if observed.Magnitude>velocity.Magnitude then velocity=observed end
   end
   motion[part]=position
   local distance=(position-root.Position).Magnitude
   if distance<1500 then
    local relative=position-root.Position
    local t=closestApproach(relative,velocity-ownVelocity,4.5+part.Size.Magnitude/4,1.5)
    if t and t<threatTime then threat=part;threatTime=t end
    if velocity.Magnitude<2.5 and distance<neutralDistance then neutral=part;neutralDistance=distance end
   end
  end
 end
 return threat,threatTime,neutral,neutralDistance
end
-- Coordinates are normalized within the bar: camera movement and UI scaling do not
-- look like cursor motion. Never claim that a previously crossed band can still be hit.
local function relativeY(y,rootY,height) return (y-rootY)/math.max(height,1) end
local function timingReady(g,band)
 if not band or g.Wrap then return false end
 if g.Predicted>=band[1] and g.Predicted<=band[2] then return true end
 if not g.Velocity or math.abs(g.Velocity)<0.001 or not g.Step or g.Step>0.1 then return false end
 local untilCenter=((band[1]+band[2])/2-g.Predicted)/g.Velocity
 return untilCenter>=0 and untilCenter<=math.min(g.Step*0.5,0.02)
end
local function gaugeFrame(now,clock,lead)
 clock=clock or cue;lead=lead or settings.Lead
 if not gauges or not visible(gauges.Root) or not visible(gauges.Marker) or not visible(gauges.Yellow) then return nil end
 local g=gauges;local top=g.Root.AbsolutePosition.Y;local height=g.Root.AbsoluteSize.Y
 local y=relativeY(g.Marker.AbsolutePosition.Y+g.Marker.AbsoluteSize.Y/2,top,height)
 local dt=clock.At and now-clock.At or 0
 local oldY=clock.MarkerY
 if clock.SampleRoot~=g.Root then oldY=nil;clock.MarkerY=nil;clock.MarkerAt=nil;clock.MarkerSpeed=nil;clock.SampleRoot=g.Root end
 local wrap=oldY and math.abs(y-oldY)>0.65
 local velocity=clock.MarkerSpeed or 0
 if oldY and math.abs(y-oldY)>0.0001 then
  -- Measure between actual cursor changes. Repeated identical render samples must
  -- not turn a later GUI update into an artificial one-frame speed spike.
  local elapsed=clock.MarkerAt and now-clock.MarkerAt or 0
  velocity=not wrap and elapsed>0 and elapsed<0.5 and (y-oldY)/elapsed or 0
  clock.MarkerAt=now;clock.MarkerY=y;clock.MarkerSpeed=velocity
 elseif not oldY then clock.MarkerAt=now;clock.MarkerY=y
 elseif clock.MarkerAt and now-clock.MarkerAt>0.08 then velocity=0 end
 local predicted=y+velocity*lead/1000
 local yellow={relativeY(g.Yellow.AbsolutePosition.Y,top,height),relativeY(g.Yellow.AbsolutePosition.Y+g.Yellow.AbsoluteSize.Y,top,height)}
 local green=g.Green and {relativeY(g.Green.AbsolutePosition.Y,top,height),relativeY(g.Green.AbsolutePosition.Y+g.Green.AbsoluteSize.Y,top,height)} or nil
 local normal=nil
 if green then
  -- normalBand's original 2-pixel minimum must be converted before normalization.
  local px=normalBand({green[1]*height,green[2]*height},{yellow[1]*height,yellow[2]*height})
  if px then normal={px[1]/height,px[2]/height} end
 end
 return {Y=y,Predicted=predicted,Yellow=yellow,Normal=normal,Green=green,Wrap=wrap,Height=1,Velocity=velocity,Step=dt,Pixel=1/math.max(height,1),SampleAt=clock.MarkerAt}
end
local function centerTiming(g,band,previous,lead)
 if not band or g.Wrap then return false end
 local center=(band[1]+band[2])/2;local width=band[2]-band[1]
 local tolerance=math.min(width*0.25,math.max((g.Pixel or 0.005)*0.75,width*0.1))
 if math.abs(g.Y-center)<=tolerance then return true,nil,tolerance end
 if previous and bandHit(previous,g.Y,center,center) and g.Y>=band[1] and g.Y<=band[2] then
  return true,nil,tolerance
 end
 local speed=g.Velocity or 0
 if math.abs(speed)>0.001 then
  local delay=(center-g.Y)/speed-math.clamp(lead or 0,0,150)/1000
  if delay>0 and delay<=0.03 then return false,delay,tolerance end
 end
 return false,nil,tolerance
end
local function catchDecision(g,perfect,previous,rescue)
 local band=perfect and g.Yellow or g.Normal
 if not band or g.Wrap then return false end
 if perfect then
  local ready,delay=centerTiming(g,band,previous,settings.Lead)
  if ready then return true,'노란 구간 중앙' end
  if delay then return false,'노란 구간 중앙 예약',delay end
 elseif (g.Y>=band[1] and g.Y<=band[2]) or timingReady(g,band) then return true,'초록 구간' end
 if perfect and rescue and previous and g.Green and g.Y>=g.Green[1] and g.Y<=g.Green[2]
  and bandHit(previous,g.Y,g.Yellow[1],g.Yellow[2]) then
  return true,'노란 구간 건너뜀 · 초록 구간 잡기 우선'
 end
 return false
end
-- Numeric charge samples are independent of the catch cursor and its state.
local function chargeDecision(clock,value,now,target,lead)
 local previous=clock.ChargeValue;local at=clock.ChargeAt
 local speed=clock.ChargeSpeed or 0
 if previous and value~=previous then
  local elapsed=at and now-at or 0
  if elapsed>0 and elapsed<0.25 then speed=(value-previous)/elapsed else speed=0 end
  clock.ChargeAt=now
 elseif not previous then clock.ChargeAt=now end
 clock.ChargeValue=value;clock.ChargeSpeed=speed
 -- Default lead=0 acts on an observed 100%, including changes between render frames.
 -- Optional lead compensation is bounded, and is never extrapolated after a fall/reset.
 if value>=target then return true,value end
 local prediction=value
 if previous and value>=previous and speed>0 and at and now-at<0.1 and value>=target-10 then
  prediction=value+speed*math.clamp(lead or 0,0,50)/1000
 end
 return prediction>=target,prediction
end
-- Throwing requires a held press and a matching release, not a catch-style click.
local function throwGaugeVisible()
 return chargeGauge and visible(chargeGauge.Percent) and (not chargeGauge.Perfect or visible(chargeGauge.Perfect)) and (not chargeGauge.Root or visible(chargeGauge.Root)) or false
end
local function pressThrowButton()
 if not actionReady('throw') then return nil,'던지기 버튼 미감지/대기' end
 if settings.ThrowInput~='클릭 충전 확인' then
  local held=ownPress(beginButton(actions.throw,true))
  if held then return held end
  if settings.ThrowInput=='길게 누르기' then return nil,'길게 누르는 입력 처리기 미지원' end
 end
 local button=actions.throw
 local wasVisible=throwGaugeVisible()
 local initial=chargeGauge and chargeNumber(chargeGauge.Percent.Text)
 local first=ownPress(beginButton(button,false,'버튼 클릭'))
 if not first then return nil,'길게 누르기와 버튼 클릭 모두 미지원' end
 first.Release()
 -- A click may start charging or may throw immediately. Do not issue a second
 -- click unless a new/changed charge gauge proves that charging actually started.
 local token={Button=button,Kind='click-charge',Confirmed=false,Initial=initial,InitialVisible=wasVisible}
 token.Release=function()
  if not token.Confirmed or not actionVisible('throw') then return true end
  local release=ownPress(beginButton(button,false,'버튼 클릭'))
  if not release then return false end
  return release.Release()
 end
 actionTransport='클릭 충전 시작 시도 · 게이지 반응 확인 중'
 return ownPress(token)
end
local throwState={Phase='idle',Acquired=nil,Started=nil,Perfect=true,Press=nil,Previous=nil,Predicted=nil,At=nil}
local function stopThrow()
 local press=throwState.Press
 throwState.Press=nil
 if press then
  local ok,result=pcall(press.Release)
  if not ok or result==false then actionError='던지기 버튼 놓기 전달 실패' end
 end
end
local function resetThrow()
 stopThrow();throwState.Phase='idle';throwState.Acquired=nil;throwState.Started=nil
 throwState.Previous=nil;throwState.Predicted=nil;throwState.At=nil
 throwState.ChargeValue=nil;throwState.ChargeAt=nil;throwState.ChargeSpeed=nil;throwState.ChargeRead=nil
end
local function throwBandReady(previous,predicted,band,height)
 if not band then return false end
 if previous and math.abs(previous-predicted)>height*0.45 then previous=nil end
 return bandHit(previous,predicted,band[1],band[2])
end
local function updateThrow(holding,now)
 if not settings.Throw or not holding then resetThrow();return end
 if throwState.Phase=='idle' then
  throwState.Phase='waiting';throwState.Acquired=now
  throwState.Perfect=choosePerfect(settings.ThrowPerfect,math.random())
 end
 if throwState.Phase=='waiting' and now-throwState.Acquired>=settings.ThrowDelay then
  local token,err=pressThrowButton()
  if not token then
   actionError=err;throwState.Phase='failed';say('자동 던지기 입력 실패 · 진단 확인');return
  end
  throwState.Press=token;throwState.Phase='charging';throwState.Started=now
  scanUI()
  say('던지기 충전 중 · '..(throwState.Perfect and '노란 구간 대기' or '일반 구간 대기'))
 end
 if throwState.Phase~='charging' then return end
 local release=false;local reason=''
 if throwGaugeVisible() then
  local value=chargeNumber(chargeGauge.Percent.Text)
  if value then
   throwState.ChargeRead=value
   local press=throwState.Press
   if press and press.Kind=='click-charge' and (not press.InitialVisible or value~=press.Initial) then press.Confirmed=true end
   local ready,predicted=chargeDecision(throwState,value,now,throwState.Perfect and 100 or 60,settings.ThrowLead)
   throwState.Predicted=predicted
   if ready and (not press or press.Kind~='click-charge' or press.Confirmed) then release=true;reason=(throwState.Perfect and '던지기 충전 100% 목표' or '던지기 일반 충전 목표')..' · 관측 '..value..'%' end
  end
 end
 local press=throwState.Press
 if press and press.Kind=='click-charge' and not press.Confirmed and now-throwState.Started>=0.35 then
  throwState.Phase='failed';stopThrow();actionError='클릭 후 충전 게이지 반응 미확인 · 추가 클릭 생략'
  say('자동 던지기 · 충전 시작 미확인');return
 end
 -- The video shows a limited possession time. Never leave the input held indefinitely.
 if not release and (now-throwState.Started>=settings.ThrowMaxHold or now-throwState.Acquired>=4.6) then
  release=true;reason='충전 제한시간 · 퍼펙트 판정 미확인'
 end
 if release then throwState.Phase='released';stopThrow();say(reason..' 던지기 놓기 입력 시도') end
end
onChargeChanged=function()
 if throwState.Phase=='charging' then updateThrow(actionVisible('throw'),os.clock()) end
end
local function updateStart(meta,now)
 if settings.Start then
  local timer=meta.Timer
  local fresh=(meta.Starting and not start.StartShown) or (start.Lobby==true and not meta.Lobby)
   or (timer and start.PreviousTimer and timer>start.PreviousTimer+15)
   or (start.PreviousTimer==nil and timer and timer>=172 and timer<=185)
  if fresh and not meta.Lobby then armStart() end
 end
 start.StartShown=meta.Starting;start.Lobby=meta.Lobby
 if meta.Timer then start.PreviousTimer=meta.Timer end
end
local function stopStart()
 if start.Moving then
  local _,root,hum=character()
  if root and hum then hum:MoveTo(root.Position) end
 end
 start.Moving=false;start.Done=true;start.Manual=false
end
local function runStart(neutral,distance,root,hum,now,threat)
 if not (settings.Start or start.Manual) or start.Done then return end
 if now>start.Until or threat then stopStart();return end
 if actionVisible('throw') then stopStart();return end
 if actionVisible('join') then return end
 local ball=start.Ball
 if not ball then ball=neutral;start.Ball=ball end
 -- Ball spawning/initial scan can lag behind the start announcement: wait within the search window.
 if not ball then return end
 if not ball.Parent or heldPart(ball) or ball.AssemblyLinearVelocity.Magnitude>4 then stopStart();return end
 if start.MoveAt==0 then start.MoveAt=now end
 local gap=(ball.Position-root.Position).Magnitude
 if gap>5 then
  start.Moving=true
  if not start.LastMove or now-start.LastMove>=0.15 then
   hum:MoveTo(Vector3.new(ball.Position.X,root.Position.Y,ball.Position.Z));start.LastMove=now
  end
  if not start.Dash and now-start.MoveAt>0.08 and invoke('dash') then start.Dash=true;say('중앙 공 방향 대시 시도') end
 elseif now-start.LastCatch>0.6 and invoke('catch') then start.LastCatch=now;say('시작 공 잡기 시도') end
end
-- Manual assistance queues normal input; it does not move the game's marker or
-- rewrite any server result. A transparent owned button captures the user's tap.
local manual={Until=0,UI=nil,Button=nil,DisplayAt=0,LastText=nil}
local function manualArmed(now)return settings.ManualAssist and manual.Until>now end
local function armManual()
 if not settings.ManualAssist then return end
 if cue.Pending then say('잡기 입력 수락 대기 중');return end
 manual.Until=os.clock()+3
 cue.Perfect=true;cue.Caught=false;cue.Attempts=0
 say('수동 잡기 예약 · 실제 노란 구간 대기 (3초)')
 if onCatchGaugeChanged then onCatchGaugeChanged() end
end
local function ensureManualUI()
 if manual.UI then return true end
 local created=nil
 local ok,err=pcall(function()
  local root=Instance.new('ScreenGui');created=root
  root.Name='KoreanHubManualCatch';root.IgnoreGuiInset=true;root.ResetOnSpawn=false;root.DisplayOrder=1000
  ownRoots[root]=true
  local button=Instance.new('TextButton');button.Name='ManualPerfectRequest';button.Text='퍼펙트 예약'
  button.BackgroundColor3=Color3.fromRGB(35,90,95);button.BackgroundTransparency=0.65
  button.TextColor3=Color3.fromRGB(255,255,255);button.TextScaled=true
  button.Active=true;button.AutoButtonColor=false;button.Visible=false;button.Parent=root
  bind(button.InputBegan,function(input)
   if not actionVisible('catch') or actionVisible('throw') then say('잡기 버튼 사용 가능 상태 대기');return end
   if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then armManual() end
  end)
  root.Parent=PG;manual.UI=root;manual.Button=button
 end)
 if not ok then
  if created then pcall(function()created:Destroy()end);ownRoots[created]=nil end
  actionError='수동 보조 UI 생성 실패: '..tostring(err);return false
 end
 return true
end
local function updateManualUI(now)
 if not settings.ManualAssist then if manual.Button then manual.Button.Visible=false end;return end
 if manual.Until>0 and now>=manual.Until then manual.Until=0;say('예약 종료 · 퍼펙트 구간을 확인하지 못함') end
 if now<manual.DisplayAt then return end
 manual.DisplayAt=now+0.1
 if not ensureManualUI() then return end
 local target=actions.catch;local show=actionVisible('catch') and not actionVisible('throw')
 manual.Button.Visible=true;manual.Button.Active=show
 local text
 if show then
  local size=target.AbsoluteSize;local center=centerOf(target)
  manual.Button.Position=UDim2.fromOffset(center.X-size.X/2,center.Y-size.Y/2)
  manual.Button.Size=UDim2.fromOffset(size.X,size.Y)
  text=cue.Pending and '입력 확인 중' or (manualArmed(now) and '노란 구간 대기' or '퍼펙트 예약')
 else
  manual.Button.Position=UDim2.new(1,-180,0.5,-90)
  manual.Button.Size=UDim2.fromOffset(150,56)
  text=actionVisible('throw') and '수동 보조 ON\n공 보유 중' or '수동 보조 ON\n잡기 버튼 찾는 중'
 end
 if text~=manual.LastText then manual.Button.Text=text;manual.LastText=text end
end
local function catchModeStatus(now)
 if settings.ManualAssist then
  local state=cue.Pending and '입력 확인 중' or (manualArmed(now) and '노란 구간 대기' or (actionVisible('throw') and '공 보유 중 · 잡기 대기' or (actionVisible('catch') and '예약 버튼 누르기 대기' or '잡기 버튼 감지 대기')))
  return '수동 퍼펙트 보조 ON · '..state
 end
 return settings.Catch and '자동 잡기 ON' or '잡기 기능 OFF'
end
-- A successful callback call is only an input attempt. Confirm acceptance from
-- possession or a newly started cooldown before blocking the rest of this cue.
local catchRoutes={'자동','버튼 클릭','마우스 콜백','가상 마우스'}
local catchRouteIndex=1
local catchRouteEvidence={}
local preferredCatchRoute=nil
local function noteCatchRoute(pending,accepted)
 local route=pending.Route or catchRoutes[catchRouteIndex]
 if pending.Transport and (pending.Transport:find('MouseButton1Click',1,true) or pending.Transport:find('Activated',1,true)) then route='버튼 클릭' end
 local evidence=catchRouteEvidence[route] or {Accepted=0,Missed=0};catchRouteEvidence[route]=evidence
 if accepted then
  evidence.Accepted=evidence.Accepted+1;evidence.Missed=0
  preferredCatchRoute=route
 elseif evidence.Accepted>0 then evidence.Missed=evidence.Missed+1 end
 if preferredCatchRoute and (catchRouteEvidence[preferredCatchRoute].Missed or 0)<3 then
  for i,name in ipairs(catchRoutes) do if name==preferredCatchRoute then catchRouteIndex=i;return end end
 end
 catchRouteIndex=catchRouteIndex%#catchRoutes+1
end
local catchStats={Attempts=0,Accepted=0,Unconfirmed=0,Last='대기'}
local function observeCatchAttempt(holding,now)
 local pending=cue.Pending
 if not pending then return end
 local cooling=false
 if now-(pending.Probed or -math.huge)>=0.035 then
  cooldownCache[pending.Button]=nil
  cooling=pending.Button and cooldown(pending.Button) or false
  pending.Probed=now
 end
 if holding or cooling then
  cue.Pending=nil;cue.Caught=true;cue.CooldownSeen=cooling
  if settings.ManualAssist then manual.Until=0 end
  catchStats.Accepted=catchStats.Accepted+1
  if inputMode=='자동' then noteCatchRoute(pending,true) end
  catchStats.Last=holding and '공 보유 전환 확인' or '잡기 입력 수락 확인 · 결과 대기'
  -- A changed cooldown confirms button acceptance, not a successful ball catch.
  return
 end
 if now-pending.At>=0.12 then
  cue.Pending=nil;catchStats.Unconfirmed=catchStats.Unconfirmed+1
  catchStats.Last='입력 수락 미확인'
  if inputMode=='자동' then noteCatchRoute(pending,false) end
 end
end
local function tryCatch(now,reason)
 if cue.Caught or cue.Pending or (cue.Attempts or 0)>=2 or now-lastCatch<0.04 then return false end
 local route=inputMode=='자동' and catchRoutes[catchRouteIndex] or nil
 if not invoke('catch',route) then
  if inputMode=='자동' then noteCatchRoute({Route=route},false) end
  lastCatch=now;return false
 end
 lastCatch=now;cue.Attempts=(cue.Attempts or 0)+1
 cue.Pending={At=now,Button=actions.catch,Route=route,Transport=actionTransport}
 catchStats.Attempts=catchStats.Attempts+1;catchStats.Last='입력 전송 · 수락 대기'
 say(reason..' 잡기 입력 시도')
 return true
end
local function reserveCatchCenter(g,now,delay)
 if cue.Pending or cue.Caught then return end
 if catchSchedule then
  if math.abs(catchSchedule.Due-(now+delay))<0.004 or now-catchSchedule.Created<0.008 then return end
  catchSchedule=nil
 end
 if (cue.TimerCount or 0)>=4 then return end
 if not g.Green or g.Y<g.Green[1] or g.Y>g.Green[2] then return end
 cue.TimerCount=(cue.TimerCount or 0)+1
 local ticket={Root=gauges and gauges.Root,Character=player.Character,Due=now+delay,Created=now}
 catchSchedule=ticket
 task.delay(delay,function()
  if catchSchedule~=ticket then return end
  catchSchedule=nil
  local current=os.clock()
  if not alive or current>ticket.Due+0.035 or ticket.Character~=player.Character then return end
  if not (settings.Catch or manualArmed(current)) or actionVisible('throw') or not actionReady('catch') then return end
  if not gauges or gauges.Root~=ticket.Root then return end
  local sample=gaugeFrame(current)
  if not sample or sample.Wrap or not sample.SampleAt then return end
  local center=(sample.Yellow[1]+sample.Yellow[2])/2
  local _,_,tolerance=centerTiming(sample,sample.Yellow,nil,settings.Lead)
  local elapsed=current-sample.SampleAt
  if elapsed<0 or elapsed>0.035 then return end
  local predicted=sample.Y+(sample.Velocity or 0)*(elapsed+settings.Lead/1000)
  local allowed=math.max(tolerance or 0,math.abs(sample.Velocity or 0)*0.003)
  if math.abs(predicted-center)<=allowed then
   local ok,err=pcall(tryCatch,current,'노란 구간 중앙 예측 예약')
   if not ok then actionError='예약 입력 오류: '..tostring(err) end
  end
 end)
end
local recentThreat=nil
local recentTTC=math.huge
local function evaluateCatch(threat,ttc,holding,now)
  local wantsCatch=settings.Catch or manualArmed(now)
  observeCatchAttempt(holding,now)
  local gauge=not holding and actionReady('catch') and gaugeFrame(now) or nil
  local incoming=not holding and (gauge~=nil or threat~=nil)
  if incoming then
   local fresh=not cue.On or (gauge and gauge.Wrap) or (gauges and cue.Root and gauges.Root~=cue.Root)
   if fresh then
    resetCue();cue.On=true;cue.Perfect=settings.ManualAssist or choosePerfect(settings.Perfect,math.random());cue.Root=gauges and gauges.Root
    gauge=not holding and actionReady('catch') and gaugeFrame(now) or nil
   end
   cue.LastSeen=now
   if wantsCatch and gauge and not cue.Caught and not cue.Pending then
    local band=cue.Perfect and gauge.Yellow or gauge.Normal
    local previous=cue.Predicted
    if previous and math.abs(previous-gauge.Predicted)>gauge.Height*0.45 then previous=nil end
    local ready,reason,delay=catchDecision(gauge,cue.Perfect,cue.Previous,settings.CatchRescue and not settings.ManualAssist)
    if ready then catchSchedule=nil;tryCatch(now,reason)
    elseif delay then reserveCatchCenter(gauge,now,delay) end
   end
   -- A valid live gauge owns catch timing. A guessed trajectory must not consume
   -- the catch before the cursor reaches the yellow/green window.
   if wantsCatch and not settings.ManualAssist and settings.Fallback and not gauge and threat and ttc<=settings.FallbackTime
    and not cue.Caught and not cue.Pending then
    tryCatch(now,'게이지 미감지 · 예상 접근 시점')
   end
   local risky=threat and ttc<=settings.DodgeTime
   local noCatch=not wantsCatch or (not gauge and not settings.Fallback) or not actionReady('catch')
    or ((cue.Caught or cue.Pending) and now-lastCatch>0.35) or (not cue.Caught and not gauge and ttc<0.04)
   if settings.Dodge and risky and noCatch and not cue.Dodged and now-lastDodge>0.7 and invoke('dodge') then
    cue.Dodged=true;lastDodge=now;say('충돌 위험 · 자동 피하기 입력 시도')
   end
   if gauge then cue.Previous=gauge.Y;cue.Predicted=gauge.Predicted;cue.At=now end
  elseif now-cue.LastSeen>0.18 or holding then resetCue() end
end
local evaluatingCatch=false
local function updateCatch(...)
 if evaluatingCatch then return end
 evaluatingCatch=true
 local ok,err=pcall(evaluateCatch,...)
 evaluatingCatch=false
 if not ok then error(err,0) end
end
onCatchGaugeChanged=function()
 if not settings.Catch and not manualArmed(os.clock()) then return end
 local _,root,hum=character()
 if not root or not hum or hum.Health<=0 then return end
 updateCatch(recentThreat,recentTTC,actionVisible('throw'),os.clock())
end
-- Performance changes are local, reversible, and never delete map/ball/UI objects.
local performance={Level=0,Generation=0,Changed=setmetatable({},{__mode='k'}),FPSOn=false,Cap=240,FPSMessage='꺼짐'}
local Lighting=nil;pcall(function()Lighting=game:GetService('Lighting')end)
local originalCap=nil
if type(getfpscap)=='function' then local ok,v=pcall(getfpscap);if ok and type(v)=='number' then originalCap=v end end
local function restoreObject(o)
 local props=performance.Changed[o]
 if not props then return end
 for prop,entry in pairs(props) do pcall(function()
  if o[prop]==entry.Applied then o[prop]=entry.Original end
 end) end
 performance.Changed[o]=nil
end
onBallRecognized=function(o)
 restoreObject(o)
 for _,child in ipairs(o:GetDescendants()) do restoreObject(child) end
end
local function change(o,prop,value)
 local ok,current=pcall(function()return o[prop]end)
 if not ok or current==value then return end
 local props=performance.Changed[o] or {};performance.Changed[o]=props
 if not props[prop] then props[prop]={Original=current} end
 local worked=pcall(function()o[prop]=value end)
 if worked then props[prop].Applied=value end
end
local function protectedVisual(o)
 local p=o
 while p and p~=workspace and p~=game do
  if parts[p] or (p:IsA('BasePart') and partCandidate(p)) then return true end
  if p:IsA('Model') and p:FindFirstChildOfClass('Humanoid') then return true end
  if p:IsA('LayerCollector') then return true end
  p=p.Parent
 end
 return false
end
local function boostObject(o)
 local level=performance.Level
 if level==0 or not o.Parent then return end
 if o:IsA('PostEffect') then change(o,'Enabled',false);return end
 if level<2 or protectedVisual(o) then return end
 -- Keep all beams/trails: they can communicate the incoming ball's path.
 if o:IsA('ParticleEmitter') then
  local props=performance.Changed[o];local old=props and props.Rate
  local rate=old and old.Original or o.Rate
  change(o,'Rate',rate*(level==2 and 0.4 or 0.15))
 end
 if level>=3 then
  if o:IsA('Texture') or o:IsA('Decal') then change(o,'Transparency',1) end
  if o:IsA('BasePart') then change(o,'CastShadow',false);change(o,'Material',Enum.Material.SmoothPlastic) end
 end
end
local function applyBoost(level)
 performance.Generation=performance.Generation+1
 local generation=performance.Generation
 performance.Level=math.clamp(math.floor(tonumber(level) or 0),0,3)
 -- A background batch avoids blocking the input/gauge frame loop on large maps.
 task.spawn(function()
  local n=0
  for o in pairs(performance.Changed) do
   if not alive or performance.Generation~=generation then return end
   restoreObject(o);n=n+1;if n%100==0 then task.wait() end
  end
  if not alive or performance.Generation~=generation or performance.Level==0 then return end
  if Lighting then change(Lighting,'GlobalShadows',false) end
  local roots={workspace};if Lighting then roots[#roots+1]=Lighting end
  for _,root in ipairs(roots) do
   for _,o in ipairs(root:GetDescendants()) do
    if not alive or performance.Generation~=generation then return end
    if protectedVisual(o) then restoreObject(o) else boostObject(o) end;n=n+1;if n%100==0 then task.wait() end
   end
  end
 end)
end
bind(workspace.DescendantAdded,function(o)
 if performance.Level>0 then task.delay(0.3,function()if alive and performance.Level>0 and o.Parent then boostObject(o) end end) end
end)
if Lighting then bind(Lighting.DescendantAdded,function(o)if performance.Level>0 then boostObject(o) end end) end
local function applyFPS(enabled)
 if type(setfpscap)~='function' then
  performance.FPSOn=false;performance.FPSMessage='미지원: setfpscap 없음';say(performance.FPSMessage);return
 end
 local target=enabled and performance.Cap or (originalCap or 60)
 local ok,err=pcall(setfpscap,target)
 if ok then performance.FPSOn=enabled;performance.FPSMessage=enabled and (target==0 and '제한 해제 요청' or tostring(target)..' FPS 제한 요청') or '원래 제한 복원'
 else performance.FPSOn=false;performance.FPSMessage='설정 실패: '..tostring(err) end
 say(performance.FPSMessage)
end
perfTab:CreateToggle({Name='FPS Unlocker · 선택 제한 적용',CurrentValue=false,Flag='DodgeFPSUnlock',Callback=function(v)applyFPS(v)end})
perfTab:CreateSlider({Name='FPS 제한 · 0 = 무제한',Range={0,360},Increment=10,CurrentValue=240,Flag='DodgeFPSCap',Callback=function(v)
 performance.Cap=math.clamp(tonumber(v) or 240,0,360);if performance.FPSOn then applyFPS(true) end
end})
perfTab:CreateSlider({Name='FPS Booster · 0 끔 / 1 약 / 2 중 / 3 강',Range={0,3},Increment=1,CurrentValue=0,Flag='DodgeBoostLevel',Callback=applyBoost})
perfTab:CreateParagraph({Title='부스터 단계',Content='1단계: 그림자·후처리 감소. 2단계: 배경 입자량 감소 추가. 3단계: 배경 텍스처·재질 단순화 추가. 공·캐릭터·판정 UI·공 궤적은 유지합니다. 0단계와 스크립트 종료 시 적용했던 값을 복원합니다. FPS Unlocker는 실행 환경의 setfpscap 지원이 필요하며 기기 성능 이상의 FPS를 만들지는 못합니다. 기존 제한을 읽을 수 없는 환경에서는 해제 시 60으로 설정합니다.'})

local scanAt,displayAt,ballManualUntil=0,0,0
local ballAt=0;local cachedBalls={nil,math.huge,nil,math.huge}
local measuredFPS=0;local frameError='' 
local meta={}
local function diagnostic()
 local out={'KoreanHub Dodgeball build 9 / verified input and movement','상태='..lastMessage,'연습 게임 표시 정확도='..tostring(practiceFeedback.Last)..'% / 표본='..practiceFeedback.Count,'연습 최고/최저='..tostring(practiceFeedback.Best)..'/'..tostring(practiceFeedback.Minimum),'입력 전달='..actionTransport,'입력 오류='..actionError,'루프 오류='..frameError,'현재 FPS='..math.floor(measuredFPS),'FPS 제한='..performance.FPSMessage,'부스터='..performance.Level,
  '던지기 충전 UI='..tostring(chargeGauge and chargeGauge.Percent:GetFullName() or '미감지'),'마지막 충전값='..tostring(throwState.ChargeRead),'잡기 입력 상태='..catchStats.Last,'잡기 전송/수락/미확인='..catchStats.Attempts..'/'..catchStats.Accepted..'/'..catchStats.Unconfirmed,'자동 입력 경로='..catchRoutes[catchRouteIndex],'수락된 우선 경로='..tostring(preferredCatchRoute),'던지기 입력 방식='..settings.ThrowInput,'수동 보조='..tostring(settings.ManualAssist)..' / 예약='..tostring(manualArmed(os.clock())),'초록 구간 구제='..tostring(settings.CatchRescue),'잡기 게이지='..tostring(gauges and gauges.Root:GetFullName() or '없음'),'잡기 퍼펙트 시도='..settings.Perfect..'%',
  '던지기='..throwState.Phase..' / 지연='..settings.ThrowDelay..'초 / 퍼펙트 시도='..settings.ThrowPerfect..'%'}
 for _,name in ipairs({'catch','dodge','dash','throw'}) do out[#out+1]=name..'='..(actions[name] and actions[name]:GetFullName() or '미감지') end
 local count=0;for p in pairs(parts) do if p.Parent then count=count+1 end end
 out[#out+1]='공 후보='..count
 return table.concat(out,'\n')
end
bind(UIS.InputBegan,function(input,processed)
 if os.clock()>ballManualUntil then return end
 if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
 if processed then return end
 local camera=workspace.CurrentCamera;if not camera then return end
 local pos=input.Position;local ray=camera:ScreenPointToRay(pos.X,pos.Y)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances=player.Character and {player.Character} or {}
 local hit=workspace:Raycast(ray.Origin,ray.Direction*1000,params)
 if hit and hit.Instance:IsA('BasePart') then manualBall=hit.Instance;parts[manualBall]=true;ballManualUntil=0;say('공 직접 지정: '..manualBall.Name) end
end)
local lastDiscovery=-math.huge
local function onFrame(dt)
 if not alive then return end
 measuredFPS=measuredFPS==0 and 1/math.max(dt,0.001) or measuredFPS*0.9+0.1/math.max(dt,0.001)
 local now=os.clock()
 -- Full discovery is capped even during GUI/VFX churn. Known markers/buttons
 -- remain cached and their current coordinates are still checked every frame/event.
 if now>=scanAt or (uiDirty and now-lastDiscovery>=0.15) then
  lastDiscovery=now
  local dirty=uiDirty;uiDirty=false;meta=scanUI();updateStart(meta,now)
  scanAt=now+(dirty and 0.25 or 0.5)
 end
 updateManualUI(now)
 local c,root,hum=character()
 if root and hum and hum.Health>0 then
  local holding=actionVisible('throw')
  updateThrow(holding,now)
  if not (settings.Catch or settings.Dodge or settings.Start or start.Manual) then
   cachedBalls={nil,math.huge,nil,math.huge};ballAt=0
  elseif now>=ballAt then
   cachedBalls={getBalls(root,ballAt>0 and now-(ballAt-0.025) or dt)};ballAt=now+0.025
  end
  local threat,ttc,neutral,distance=cachedBalls[1],cachedBalls[2],cachedBalls[3],cachedBalls[4]
  recentThreat=threat;recentTTC=ttc
  updateCatch(threat,ttc,holding,now)
  runStart(neutral,distance,root,hum,now,threat)
 else resetThrow() end
 if now>=displayAt then
  paragraph(status,'상태',catchModeStatus(now)..'\n'..lastMessage..'\n퍼펙트 시도 확률 '..settings.Perfect..'% · 자동 잡기 '..(settings.Catch and 'ON' or 'OFF')..' / 피하기 '..(settings.Dodge and 'ON' or 'OFF')..'\n던지기 '..(settings.Throw and 'ON' or 'OFF')..' · 대기 '..settings.ThrowDelay..'초 · 퍼펙트 시도 '..settings.ThrowPerfect..'%')
  paragraph(detail,'감지 결과',diagnostic());displayAt=now+1
 end
end
bind(Run.RenderStepped,function(dt)
 local ok,err=pcall(onFrame,dt)
 if not ok then frameError=tostring(err);lastMessage='처리 오류 · 진단 확인' end
end)
local automationUI={}
local manualControl=nil
local function setAllAutomation(enabled)
 settings.ManualAssist=false;manual.Until=0;updateManualUI(os.clock())
 if manualControl then pcall(function()manualControl:Set(false)end) end
 settings.Catch=enabled;settings.Dodge=enabled;settings.Start=enabled;settings.Throw=enabled
 for _,control in pairs(automationUI) do pcall(function()control:Set(enabled)end) end
 resetCue();resetThrow();scanAt=0
 if not enabled then start.Until=0;stopStart()
 elseif meta.Timer and meta.Timer>=172 and meta.Timer<=185 and not meta.Lobby then armStart() end
 say(enabled and '자동 잡기 · 피하기 · 시작 공 · 던지기 모두 켜짐' or '자동 기능 모두 꺼짐')
end
tab:CreateButton({Name='자동 기능 모두 켜기',Callback=function()setAllAutomation(true)end})
tab:CreateButton({Name='자동 기능 모두 끄기',Callback=function()setAllAutomation(false)end})
automationUI.Catch=tab:CreateToggle({Name='자동 잡기',CurrentValue=true,Flag='DodgeCatch',Callback=function(v)settings.Catch=v;if v then settings.ManualAssist=false;manual.Until=0;updateManualUI(os.clock());if manualControl then pcall(function()manualControl:Set(false)end) end end;resetCue();say(v and '자동 잡기 켜짐 · 게이지 대기' or '자동 잡기 꺼짐')end})
manualControl=tab:CreateToggle({Name='직접 누르기 · 퍼펙트 타이밍 보조',CurrentValue=false,Flag='DodgeManualAssist',Callback=function(v)
 if v and not ensureManualUI() then say('수동 보조 UI 생성 실패 · 진단 확인');return end
 settings.ManualAssist=v;manual.Until=0;resetCue();scanAt=0
 if v then
  settings.Catch=false;settings.Dodge=false;settings.Start=false;start.Until=0;stopStart()
  for _,name in ipairs({'Catch','Dodge','Start'}) do local control=automationUI[name];if control then pcall(function()control:Set(false)end) end end
  say('수동 보조 ON · 자동 잡기는 별도로 OFF · 퍼펙트 예약 버튼을 누르세요.')
 else say('수동 보조 꺼짐 · 자동 잡기는 별도로 켜세요.') end
 updateManualUI(os.clock())
end})
tab:CreateParagraph({Title='정확도 표시',Content='잡기는 노란 구간 진입 즉시가 아닌 중앙을 목표로 합니다. 기본 추가 지연 보정은 0ms입니다. 연습의 정확도 문구가 감지되면 감지/진단 탭에 게임이 표시한 수치 그대로 기록합니다. 이 수치는 실전 잡기 성공률과 별개이며 100% 성공을 보장하지 않습니다.'})
tab:CreateParagraph({Title='수동 퍼펙트 보조',Content='이 기능을 켜면 잡기 버튼 자리에 퍼펙트 예약 버튼이 표시됩니다. 직접 누르면 최대 3초 동안 실제 노란 구간을 기다린 뒤 잡기 입력을 보냅니다. 자동 잡기·피하기·시작 공은 이 모드에서 꺼집니다. 판정선을 옮기거나 아무 시점의 입력을 퍼펙트로 바꾸지는 않습니다. 구간이 이미 지났거나 입력 전달이 지원되지 않으면 실패할 수 있습니다.'})
tab:CreateToggle({Name='노란 구간 놓치면 초록 구간 잡기 우선' ,CurrentValue=true,Flag='DodgeCatchRescue',Callback=function(v)settings.CatchRescue=v end})
tab:CreateSlider({Name='노란 퍼펙트 시도 확률 (%)',Range={0,100},Increment=1,CurrentValue=100,Flag='DodgePerfect',Callback=function(v)settings.Perfect=math.clamp(tonumber(v) or 100,0,100)end})
automationUI.Dodge=tab:CreateToggle({Name='자동 피하기 · 잡기 위험 시 회피',CurrentValue=false,Flag='DodgeAvoid',Callback=function(v)settings.Dodge=v end})
automationUI.Start=tab:CreateToggle({Name='자동 시작 공 잡기 + 대시',CurrentValue=false,Flag='DodgeOpening',Callback=function(v)settings.Start=v;if not v then start.Until=0;stopStart()
 elseif meta.Timer and meta.Timer>=172 and meta.Timer<=185 and not meta.Lobby then armStart()
 else say('다음 경기 시작 공 대기') end end})
tab:CreateButton({Name='지금 시작 공 찾기 · 1회',Callback=function()armStart(true)end})
tab:CreateToggle({Name='게이지 미감지 시 예상 접근 잡기',CurrentValue=true,Flag='DodgeFallback',Callback=function(v)settings.Fallback=v end})
tab:CreateSlider({Name='예상 접근 잡기 시간 (초)',Range={0.03,0.3},Increment=0.01,CurrentValue=0.10,Flag='DodgeFallbackTime',Callback=function(v)settings.FallbackTime=tonumber(v) or 0.10 end})
tab:CreateSlider({Name='잡기 추가 지연 보정 (ms) · 기본 0',Range={0,150},Increment=1,CurrentValue=0,Flag='DodgeLead',Callback=function(v)settings.Lead=tonumber(v) or 0 end})
tab:CreateSlider({Name='피하기 위험 시간 (초)',Range={0.05,0.5},Increment=0.01,CurrentValue=0.20,Flag='DodgeRisk',Callback=function(v)settings.DodgeTime=tonumber(v) or 0.20 end})
tab:CreateSlider({Name='시작 공 탐색 시간 (초)',Range={3,15},Increment=1,CurrentValue=8,Flag='DodgeSeek',Callback=function(v)settings.StartSeconds=tonumber(v) or 8 end})
automationUI.Throw=throwTab:CreateToggle({Name='자동 던지기',CurrentValue=false,Flag='DodgeAutoThrow',Callback=function(v)settings.Throw=v;if not v then resetThrow()end end})
throwTab:CreateDropdown({Name='던지기 입력 방식',Options={'자동','길게 누르기','클릭 충전 확인'},CurrentOption={'자동'},MultipleOptions=false,Flag='DodgeThrowInput',Callback=function(v)resetThrow();settings.ThrowInput=type(v)=='table' and v[1] or v end})
throwTab:CreateSlider({Name='공을 잡은 뒤 던지기 대기 (초)',Range={0,4},Increment=0.1,CurrentValue=0.5,Flag='DodgeThrowDelay',Callback=function(v)settings.ThrowDelay=math.clamp(tonumber(v) or 0.5,0,4)end})
throwTab:CreateSlider({Name='던지기 퍼펙트 시도 확률 (%)',Range={0,100},Increment=1,CurrentValue=100,Flag='DodgeThrowPerfect',Callback=function(v)settings.ThrowPerfect=math.clamp(tonumber(v) or 100,0,100)end})
throwTab:CreateSlider({Name='던지기 놓기 선행 보정 (ms) · 기본 0',Range={0,50},Increment=1,CurrentValue=0,Flag='DodgeThrowLead',Callback=function(v)settings.ThrowLead=tonumber(v) or 0 end})
throwTab:CreateSlider({Name='최대 충전 대기 (초)',Range={0.3,3},Increment=0.1,CurrentValue=1.5,Flag='DodgeThrowHold',Callback=function(v)settings.ThrowMaxHold=tonumber(v) or 1.5 end})
throwTab:CreateParagraph({Title='던지기 사용 방법',Content='자동 던지기를 켜고 카메라로 방향을 맞추세요. 던지기는 PERFECT 표시 아래의 충전 %를 별도로 읽고, 퍼펙트 시도에서는 100%를 목표로 버튼을 놓습니다. 기본 선행 보정 0은 실제 표시값을 기준으로 하며 숫자 변경 즉시 반응합니다. 공을 잡으면 설정한 시간만큼 기다린 뒤 버튼을 누른 상태로 충전하고 목표 구간에서 놓습니다. 대기 슬라이더는 충전을 시작하기 전의 시간이며 실제 투척은 목표 구간에 도달한 뒤 이뤄집니다. 공 보유 제한시간이 가까워지거나 게이지를 찾지 못하면 최대 충전 시간 후 놓습니다. 퍼펙트 확률은 해당 구간을 노리는 시도 비율이며 서버의 실제 성공률을 보장하지 않습니다. 기능 해제·사망·공 소유 종료 시 잡고 있던 버튼을 놓습니다.'})
info:CreateDropdown({Name='자동 입력 전달 방식',Options={'자동','터치 콜백','버튼 클릭','마우스 콜백','가상 마우스'},CurrentOption={'자동'},MultipleOptions=false,Flag='DodgeInputMode',Callback=function(v)resetThrow();inputMode=type(v)=='table' and v[1] or v;actionError='';say('입력 방식: '..tostring(inputMode))end})
info:CreateButton({Name='잡기 자동 입력 테스트 · 1회',Callback=function()invoke('catch')end})
info:CreateButton({Name='게임 UI 다시 감지',Callback=function()meta=scanUI();say('버튼과 게이지 재감지 완료')end})
info:CreateButton({Name='공 직접 지정 · 누른 뒤 공 터치',Callback=function()task.delay(0.4,function()if alive then ballManualUntil=os.clock()+8;say('8초 안에 공을 터치하세요.')end end)end})
info:CreateButton({Name='진단 복사',Callback=function()local text=diagnostic();if type(setclipboard)=='function' then pcall(setclipboard,text);say('진단 복사 완료')else paragraph(detail,'진단',text);say('복사 기능 없음 · 감지/진단 탭에 표시')end end})
info:CreateParagraph({Title='사용 방법',Content='자동 잡기·피하기·시작 공 잡기를 각각 켜세요. 흰 판정선이 프레임 사이에서 노란 구간을 건너뛰면 초록 구간에서 잡기를 시도하는 구제가 기본 ON입니다. 이는 퍼펙트 성공으로 표시하지 않습니다. 퍼펙트 100%는 매 공마다 노란 구간을 노리는 설정이며 게임의 성공률을 보장하지 않습니다. 잡기 0%는 초록 구간, 던지기 0%는 일반 충전 60%를 목표로 합니다. 게이지가 보이지 않으면 공의 예상 접근 시간으로 잡기를 시도하며 이 경우 퍼펙트 구간 판정은 미확인입니다. 잡기와 피하기를 함께 켜면 잡기를 먼저 시도합니다. 던지기 버튼이 보이면 잡기를 멈춥니다. 시작 공은 새 경기 안내·타이머 재시작·로비에서 경기 전환을 확인해 이동과 대시를 시도합니다. 게임 시작 시점이 감지되지 않으면 1회 버튼을 사용할 수 있습니다. 화면 UI와 입력 전달 방식은 실행 환경에 따라 달라질 수 있으며 진단에서 확인할 수 있습니다.'})
bind(player.CharacterAdded,function()manual.Until=0;resetCue();resetThrow();motion={};rootMotion={};cachedBalls={nil,math.huge,nil,math.huge};ballAt=0;start.Done=true;start.Until=0 end)
env.KoreanDodgeCleanup=function()
 alive=false;settings.ManualAssist=false;manual.Until=0
 if manual.UI then pcall(function()manual.UI:Destroy()end) end
 settings.Catch=false;settings.Dodge=false;settings.Start=false;settings.Throw=false;resetThrow()
 for token in pairs(activePresses) do pcall(token.Release) end
 performance.Generation=performance.Generation+1;performance.Level=0
 for o in pairs(performance.Changed) do restoreObject(o) end
 if performance.FPSOn then applyFPS(false) end
 for _,c in ipairs(links) do pcall(function()c:Disconnect()end) end
 local _,root,hum=character();if root and hum then pcall(function()hum:MoveTo(root.Position)end)end
 pcall(function()Rayfield:Destroy()end)
end
say('자동 잡기 켜짐 · 노란 구간 우선 / 놓치면 초록 구간 잡기')
