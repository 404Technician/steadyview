-- SteadyView: modular motion-comfort toolkit for WoW: Forever.
-- All effects are optional. The addon is not medical treatment.
local ADDON = ...
local SV = CreateFrame("Frame", "SteadyViewController", UIParent)
local config, overlays, window, editor, widgets = nil, {}, nil, nil, {}
local defaults = {
  enabled=true,
  dots={enabled=true,count=12,size=12,scale=1.00,alpha=0.65,color={1,1,1},regions={top=true,bottom=true,left=true,right=true},band=20,margin=4,mode="random-adjust",points={},protected={},},
  focus={enabled=false,size=13,pointSize=3,alpha=0.65,color={1,1,1},shape="ring",offsetX=0,offsetY=0},
  lines={enabled=false,alpha=0.35,size=8,position="sides",edges={left=true,right=true,top=false,bottom=false},inset=12,color={1,1,1}},
  vignette={enabled=false,alpha=0.25,width=16},
  movement={enabled=false,threshold=1,alpha=0.30},
  dynamic={enabled=false,alpha=0.30,fade=0.25},
  camera={enabled=false,settings={}},
  profile="Default",profiles={},
}
local function copy(t) if type(t)~="table" then return t end local n={} for k,v in pairs(t) do n[k]=copy(v) end return n end
local function merge(d,s)
  if type(s)~="table" then return copy(d) end
  local r=copy(d)
  for k,v in pairs(s) do if type(v)=="table" and type(r[k])=="table" then r[k]=merge(r[k],v) elseif type(v)~="function" then r[k]=v end end
  return r
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function report(s) print("|cff77ddeeSteadyView:|r "..s) end
local function makeTexture(parent,layer)
  local t=parent:CreateTexture(nil,layer or "ARTWORK") t:SetColorTexture(1,1,1,1) return t
end
local function safeCVarGet(k)
  if C_CVar and type(C_CVar.GetCVar)=="function" then local ok,v=pcall(C_CVar.GetCVar,k); if ok then return v end end
  if type(GetCVar)=="function" then local ok,v=pcall(GetCVar,k); if ok then return v end end
end
local function safeCVarSet(k,v)
  if C_CVar and type(C_CVar.SetCVar)=="function" then local ok=pcall(C_CVar.SetCVar,k,tostring(v));return ok end
  if type(SetCVar)=="function" then local ok=pcall(SetCVar,k,tostring(v));return ok end
  return false
end
local cameraOptions={
  {key="cameraShake",label="Reduce camera shake",cvar="ShakeStrengthCamera",value="0",help="Attempts to reduce camera shake. Only applied if this client exposes the CVar."},
  {key="cameraKeepCharacterCentered",label="Keep character centered",cvar="CameraKeepCharacterCentered",value="1",help="Tries to use your character as a stable visual reference."},
  {key="cameraReduceUnexpectedMovement",label="Reduce unexpected camera movement",cvar="CameraReduceUnexpectedMovement",value="1",help="Limits camera movements not deliberately made by the player, if supported."},
  {key="motionSicknessFocalCircle",label="Client focal circle",cvar="motionSicknessFocalCircle",value="1",help="Uses a built-in focal circle if supported by the game client."},
  {key="motionSicknessLandscapeDarkening",label="Client landscape darkening",cvar="motionSicknessLandscapeDarkening",value="1",help="Enables built-in environmental edge shading if available."},
}
local originalCVars={}
local cameraStatus={}
local cameraStatusTexts={}
local function applyCamera()
  if not config then return end
  for _,o in ipairs(cameraOptions) do
    local now=safeCVarGet(o.cvar)
    local use=config.enabled and config.camera.enabled and config.camera.settings[o.key]
    if use and now~=nil and now~="" then
      if originalCVars[o.cvar]==nil then originalCVars[o.cvar]=now end
      local ok=safeCVarSet(o.cvar,o.value)
      local after=safeCVarGet(o.cvar)
      cameraStatus[o.key]=(ok and tostring(after)==o.value) and "Applied" or "Blocked by client"
    elseif use then cameraStatus[o.key]="Unsupported / missing CVar"
    else cameraStatus[o.key]="Disabled" end
    if not use and originalCVars[o.cvar]~=nil then
      safeCVarSet(o.cvar,originalCVars[o.cvar]);originalCVars[o.cvar]=nil
    end
  end
end
local dotLayer=CreateFrame("Frame","SteadyViewDotLayer",UIParent)
dotLayer:SetAllPoints(UIParent);dotLayer:SetFrameStrata("HIGH");dotLayer:EnableMouse(false)
local dotFrames={}
local dotDragEnabled=false
local focusLayer=CreateFrame("Frame",nil,UIParent);focusLayer:SetAllPoints(UIParent);focusLayer:SetFrameStrata("HIGH");focusLayer:EnableMouse(false)
local focusElements={}
local lineLayer=CreateFrame("Frame",nil,UIParent);lineLayer:SetAllPoints(UIParent);lineLayer:SetFrameStrata("HIGH");lineLayer:EnableMouse(false)
local lineElements={}
local vignetteLayer=CreateFrame("Frame",nil,UIParent);vignetteLayer:SetAllPoints(UIParent);vignetteLayer:SetFrameStrata("MEDIUM");vignetteLayer:EnableMouse(false)
local vignetteElements={}
local function uiSize() return math.max(UIParent:GetWidth(),200),math.max(UIParent:GetHeight(),200) end
local function intersects(x,y,z)
  for _,rect in ipairs(config.dots.protected) do
    if x>=rect[1] and x<=rect[3] and y>=rect[2] and y<=rect[4] then return true end
  end
  -- Protected UI rectangles only affect random placement; manually positioned dots stay wherever placed.
  -- Defaults: configurable protected zones supplement these sensible initial exclusions.
  if y<0.14 and x<0.34 then return true end
  if y<0.24 and x>0.75 then return true end
  if y>0.84 and x>0.21 and x<0.79 then return true end
  return false
end
local function acceptable(x,y)
  local d=config.dots;local m=clamp(d.margin/100,0,0.30);local band=clamp(d.band/100,m+0.01,0.49)
  if x<m or x>1-m or y<m or y>1-m or intersects(x,y) then return false end
  return (d.regions.top and y<=band) or (d.regions.bottom and y>=1-band) or (d.regions.left and x<=band) or (d.regions.right and x>=1-band)
end
local function randomize()
  if not config then return end
  local pts={} local n=config.dots.count
  for i=1,n do
    local found=false
    for try=1,300 do
      local x=math.random();local y=math.random()
      if acceptable(x,y) then
        local distant=true
        for _,p in ipairs(pts) do if (p.x-x)^2+(p.y-y)^2 < 0.0005 then distant=false;break end end
        if distant then pts[i]={x=x,y=y};found=true;break end
      end
    end
    if not found then pts[i]={x=clamp(0.1+(i%7)*0.11,0.01,0.99),y=clamp((config.dots.margin+1)/100,0.01,0.99)} end
  end
  config.dots.points=pts
end
local function save() if config then SteadyViewDB=copy(config) end end
local function refreshDots()
  if not config then return end
  local d=config.dots
  for _,f in ipairs(dotFrames) do f:Hide();f:EnableMouse(false) end
  if not config.enabled or not d.enabled then return end
  if #d.points~=d.count then randomize() end
  local w,h=uiSize()
  for i,p in ipairs(d.points) do
    local f=dotFrames[i]
    if not f then
      f=CreateFrame("Frame",nil,dotLayer);f:SetFrameStrata("TOOLTIP")
      -- Anti-aliased transparent circle; no stripes and no client-dependent mask APIs.
      f.circle=f:CreateTexture(nil,"ARTWORK")
      f.circle:SetAllPoints(f)
      f.circle:SetTexture("Interface\\AddOns\\steadyview\\Circle.tga")
      f:SetMovable(true);f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart",function(self)
        if dotDragEnabled then self:StartMoving() end
      end)
      f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter()
        local point=config.dots.points[self.dotIndex]
        local currentW,currentH=uiSize()
        if point and cx and cy then
          local parentLeft=UIParent:GetLeft() or 0
          local parentBottom=UIParent:GetBottom() or 0
          point.x=clamp((cx-parentLeft)/currentW,0.005,0.995)
          point.y=clamp(1-(cy-parentBottom)/currentH,0.005,0.995)
          self:ClearAllPoints()
          self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",point.x*currentW,(1-point.y)*currentH)
          save()
        end
      end)
      dotFrames[i]=f
    end
    f.dotIndex=i
    local actualSize=clamp((d.size or 12)*(d.scale or 1),2,180)
    f:SetSize(actualSize,actualSize);f:ClearAllPoints()
    f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",p.x*w,(1-p.y)*h)
    f.circle:SetVertexColor(d.color[1],d.color[2],d.color[3],d.alpha)
    f:EnableMouse(dotDragEnabled)
    f:Show()
  end
end
local function square(layer,cache,i)
  if not cache[i] then cache[i]=makeTexture(layer) end return cache[i]
end
local focusDot
local function refreshFocus()
  for _,t in ipairs(focusElements) do t:Hide() end
  if focusDot then focusDot:Hide() end
  if not config or not config.enabled or not config.focus.enabled then return end
  local a=config.focus;local w,h=uiSize();local x=a.offsetX*w/100;local y=a.offsetY*h/100
  if a.shape=="dot" then
    if not focusDot then
      focusDot=focusLayer:CreateTexture(nil,"ARTWORK")
      focusDot:SetTexture("Interface\\AddOns\\steadyview\\Circle.tga")
    end
    focusDot:ClearAllPoints()
    focusDot:SetPoint("CENTER",UIParent,"CENTER",x,y)
    focusDot:SetSize(clamp(a.size,2,120),clamp(a.size,2,120))
    focusDot:SetVertexColor(a.color[1],a.color[2],a.color[3],a.alpha)
    focusDot:Show()
    return
  end
  local segs=a.shape=="cross" and 4 or 32
  for i=1,segs do
    local t=focusElements[i]
    if not t then
      t=focusLayer:CreateTexture(nil,"ARTWORK")
      t:SetTexture("Interface\\AddOns\\steadyview\\Circle.tga")
      focusElements[i]=t
    end
    local angle=(i-1)*2*math.pi/segs
    local dx,dy
    if a.shape=="cross" then dx=({-1,1,0,0})[i]*a.size;dy=({0,0,-1,1})[i]*a.size else dx=math.cos(angle)*a.size;dy=math.sin(angle)*a.size end
    t:ClearAllPoints();t:SetPoint("CENTER",UIParent,"CENTER",x+dx,y+dy)
    local pointSize=clamp(a.pointSize or 3,1,48)
    t:SetSize(pointSize,pointSize)
    t:SetVertexColor(a.color[1],a.color[2],a.color[3],a.alpha);t:Show()
  end
end
local function refreshLines()
  for _,t in ipairs(lineElements) do t:Hide() end
  if not config or not config.enabled or not config.lines.enabled then return end
  local a=config.lines; local w,h=uiSize();local p=a.inset/100
  local specs={}
  local e=a.edges or {left=(a.position=="sides" or a.position=="all"),right=(a.position=="sides" or a.position=="all"),top=(a.position=="topbottom" or a.position=="all"),bottom=(a.position=="topbottom" or a.position=="all")}
  if e.left then specs[#specs+1]={x=w*p,y=h/2,width=a.size,height=h*(1-2*p)} end
  if e.right then specs[#specs+1]={x=w*(1-p),y=h/2,width=a.size,height=h*(1-2*p)} end
  if e.top then specs[#specs+1]={x=w/2,y=h*(1-p),width=w*(1-2*p),height=a.size} end
  if e.bottom then specs[#specs+1]={x=w/2,y=h*p,width=w*(1-2*p),height=a.size} end
  for i,v in ipairs(specs) do local t=square(lineLayer,lineElements,i);t:ClearAllPoints();t:SetPoint("CENTER",UIParent,"BOTTOMLEFT",v.x,v.y);t:SetSize(v.width,v.height);t:SetColorTexture(a.color[1],a.color[2],a.color[3],a.alpha);t:Show() end
end
local vignetteStrength=0
local motionBandExcess=0
-- The preview countdown belongs to a Frame, never a FontString OnUpdate handler.
local previewFrame=CreateFrame("Frame",nil,UIParent)
previewFrame:SetFrameStrata("TOOLTIP")
previewFrame:SetSize(280,130)
previewFrame:SetPoint("CENTER",UIParent,"CENTER",0,105)
previewFrame:EnableMouse(false)
local previewNumber=previewFrame:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
previewNumber:SetPoint("CENTER",previewFrame,"CENTER",0,0)
previewNumber:SetTextColor(1,0.9,0.4,1)
local previewCaption=previewFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
previewCaption:SetPoint("TOP",previewNumber,"BOTTOM",0,-8)
previewCaption:SetText("Darkening test")
previewFrame:Hide()
local function refreshVignette()
  for _,t in ipairs(vignetteElements) do t:Hide() end
  if not config or not config.enabled then return end
  local a=config.vignette
  local strength=(a.enabled and a.alpha or 0)+vignetteStrength
  strength=clamp(strength,0,1.6)
  strength=1-math.exp(-strength*1.8)
  if strength<=0 then return end
  local w,h=uiSize();local steps=24
  -- Above strength 1.0, active motion protection increases the inward reach
  -- rather than requesting an invalid alpha greater than 1.0.
  local band=clamp(a.width,5,40)/100 + clamp(motionBandExcess,0,0.6)*0.40
  band=clamp(band,0.05,0.65)
  -- Per-step strips form a low-overhead, stepped gradient around the image.
  for side=1,4 do for j=1,steps do
    local idx=(side-1)*steps+j;local t=square(vignetteLayer,vignetteElements,idx)
    local depth=(j-0.5)/steps;local opacity=strength*(1-depth)^2
    t:SetColorTexture(0,0,0,opacity);t:ClearAllPoints()
    if side<3 then
      t:SetSize(w*band/steps+1,h)
      if side==1 then t:SetPoint("LEFT",UIParent,"LEFT",(j-1)*w*band/steps,0) else t:SetPoint("RIGHT",UIParent,"RIGHT",-(j-1)*w*band/steps,0) end
    else
      t:SetSize(w,h*band/steps+1)
      if side==3 then t:SetPoint("TOP",UIParent,"TOP",0,-(j-1)*h*band/steps) else t:SetPoint("BOTTOM",UIParent,"BOTTOM",0,(j-1)*h*band/steps) end
    end
    t:Show()
  end end
end
local function refreshCameraStatusTexts()
  for key,label in pairs(cameraStatusTexts) do
    if label and label.SetText then
      local state=nil
      for _,o in ipairs(cameraOptions) do if o.key==key then state=safeCVarGet(o.cvar); break end end
      label:SetText(cameraStatus[key] or ((state~=nil and state~="") and ("Detected: "..tostring(state)) or "Unsupported"))
    end
  end
end
local function refreshAll()
  if not config then return end
  refreshDots();refreshFocus();refreshLines();refreshVignette();applyCamera();refreshCameraStatusTexts();save()
end
local function title(parent,txt,y)
  local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormalLarge") f:SetPoint("TOPLEFT",parent,"TOPLEFT",15,y);f:SetText(txt);f:SetTextColor(0.90,0.78,0.38,1) return f
end
local function textLine(parent,txt,x,y,width)
  local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);f:SetWidth(width or 390);f:SetJustifyH("LEFT");f:SetText(txt);f:SetTextColor(0.88,0.92,0.95,1);return f
end
local function button(parent,label,x,y,w,h,fn)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(w,h or 24);b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn);return b
end
local function check(parent,label,x,y,get,set,help)
  local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
  b:SetChecked(get());b:SetScript("OnClick",function(self) set(not not self:GetChecked());refreshAll() end)
  local t=textLine(parent,label,x+29,y-6,330)
  if help then b:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(label);GameTooltip:AddLine(help,1,1,1,true);GameTooltip:Show() end);b:SetScript("OnLeave",function() GameTooltip:Hide() end) end
  return b,t
end
local function slider(parent,label,x,y,minv,maxv,step,get,set,help)
  local id="SteadyViewSlider"..#widgets+1
  local s=CreateFrame("Slider",id,parent,"OptionsSliderTemplate")
  s:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);s:SetSize(215,17);s:SetMinMaxValues(minv,maxv);s:SetValueStep(step);s:SetObeyStepOnDrag(true);s:SetValue(get())
  _G[id.."Low"]:SetText(tostring(minv));_G[id.."High"]:SetText(tostring(maxv))
  local v=textLine(parent,"",x+225,y+1,100)
  local function show(n) v:SetText(label..": "..(step<1 and string.format("%.2f",n) or tostring(math.floor(n+0.5)))) end
  show(get());s:SetScript("OnValueChanged",function(_,n) local rounded=math.floor(n/step+0.5)*step;set(rounded);show(rounded);refreshAll() end)
  if help then s:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(label);GameTooltip:AddLine(help,1,1,1,true);GameTooltip:Show() end);s:SetScript("OnLeave",function() GameTooltip:Hide() end) end
  widgets[#widgets+1]=s;return s
end
local function panel(parent)
  local f=CreateFrame("Frame",nil,parent,"BackdropTemplate");f:SetAllPoints(parent)
  f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
  f:SetBackdropColor(0.04,0.08,0.12,0.97);return f
end
local function makeWindow()
  window=CreateFrame("Frame","SteadyViewSettings",UIParent,"BackdropTemplate")
  window:Hide()
  window:SetSize(660,515);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:EnableMouse(true)
  window:SetMovable(true);window:RegisterForDrag("LeftButton");window:SetScript("OnDragStart",window.StartMoving);window:SetScript("OnDragStop",window.StopMovingOrSizing)
  panel(window)
  title(window,"SteadyView  |  Motion Comfort Toolkit",-15)
  textLine(window,"Every aid is optional. Hover over a control for details. /steadyview to open.",17,-43,615)
  button(window,"X",619,-12,25,22,function() window:Hide() end)
  local pages={} local tabs={"Dots","Focus","Edges","Movement","Camera","Profiles"}
  local selectedPage=1
  local function showPage(index)
    selectedPage=index
    for j,page in ipairs(pages) do
      if j==index then page:Show() else page:Hide() end
    end
  end
  for i,name in ipairs(tabs) do
    local page=CreateFrame("Frame",nil,window);page:SetPoint("TOPLEFT",window,"TOPLEFT",14,-103);page:SetSize(630,395);page:Hide();pages[i]=page
    button(window,name,12+(i-1)*106,-70,101,25,function()
      showPage(i)
    end)
  end
  local p=pages[1]
  title(p,"Fixed Reference Dots",-8)
  textLine(p,"Stationary screen markers. Randomize them, drag each dot, then lock the layout.",16,-35,600)
  check(p,"Enable reference dots",12,-61,function() return config.dots.enabled end,function(v) config.dots.enabled=v end,"Dots are fixed to the screen, not the camera or world. They do not block clicks while locked.")
  slider(p,"Count",22,-108,1,40,1,function()return config.dots.count end,function(v) config.dots.count=v;config.dots.points={} end)
  slider(p,"Size (pixels)",22,-150,2,100,1,function()return config.dots.size end,function(v) config.dots.size=v end)
  slider(p,"Scale",22,-192,0.50,2.00,0.05,function()return config.dots.scale or 1 end,function(v) config.dots.scale=v end)
  slider(p,"Opacity",22,-234,0.05,1,0.05,function()return config.dots.alpha end,function(v) config.dots.alpha=v end)
  slider(p,"Edge band %",22,-276,5,49,1,function()return config.dots.band end,function(v) config.dots.band=v;randomize() end)
  slider(p,"Margin %",22,-318,0,30,1,function()return config.dots.margin end,function(v) config.dots.margin=v;randomize() end)
  local regions={{"Top","top"},{"Bottom","bottom"},{"Left","left"},{"Right","right"}}
  for i,r in ipairs(regions) do check(p,r[1],365,-91-(i-1)*37,function()return config.dots.regions[r[2]] end,function(v)config.dots.regions[r[2]]=v;randomize() end,"Allows random dots in this part of the screen.") end
  button(p,"Randomize",365,-245,110,25,function() randomize();refreshAll() end)
  button(p,"Edit positions",485,-245,130,25,function() window:Hide();SV:OpenEditor() end)
  button(p,"White",365,-285,75,24,function()config.dots.color={1,1,1};refreshAll() end)
  button(p,"Cyan",444,-285,75,24,function()config.dots.color={0.45,0.9,1};refreshAll() end)
  button(p,"Amber",523,-285,86,24,function()config.dots.color={1,0.75,0.35};refreshAll() end)
  textLine(p,"Protected areas: default player portrait, minimap and action bars. Add custom zones in Edit mode.",15,-338,610)
  p=pages[2];title(p,"Static Focus Point",-8)
  textLine(p,"Provides a small, stationary central reference. You can adjust shape and position.",16,-36,600)
  check(p,"Enable focus marker",12,-64,function()return config.focus.enabled end,function(v)config.focus.enabled=v end,"A visual reference may help some players; others find it distracting.")
  slider(p,"Size",23,-119,3,120,1,function()return config.focus.size end,function(v)config.focus.size=v end)
  slider(p,"Opacity",23,-164,0.05,1,0.05,function()return config.focus.alpha end,function(v)config.focus.alpha=v end)
  slider(p,"Horizontal %",23,-209,-40,40,1,function()return config.focus.offsetX end,function(v)config.focus.offsetX=v end)
  slider(p,"Vertical %",23,-254,-40,40,1,function()return config.focus.offsetY end,function(v)config.focus.offsetY=v end)
  slider(p,"Cross point size",23,-299,1,48,1,function()return config.focus.pointSize or 3 end,function(v)config.focus.pointSize=v end,"Controls the thickness of each of the four cross markers. Also affects circle marker thickness.")
  button(p,"Circle",365,-117,76,25,function()config.focus.shape="ring";refreshAll() end)
  button(p,"Cross",450,-117,76,25,function()config.focus.shape="cross";refreshAll() end)
  button(p,"Dot",535,-117,76,25,function()config.focus.shape="dot";refreshAll() end)
  button(p,"White",365,-164,75,24,function()config.focus.color={1,1,1};refreshAll() end)
  button(p,"Cyan",444,-164,75,24,function()config.focus.color={0.45,0.9,1};refreshAll() end)
  button(p,"Amber",523,-164,86,24,function()config.focus.color={1,0.75,0.35};refreshAll() end)
  p=pages[3];title(p,"Screen Edges",-8)
  textLine(p,"Optional fixed reference lines and peripheral darkening. All strengths are adjustable.",16,-35,600)
  check(p,"Reference lines",12,-60,function()return config.lines.enabled end,function(v)config.lines.enabled=v end,"Static lines can act as orientation landmarks.")
  slider(p,"Line opacity",22,-107,0.05,1,0.05,function()return config.lines.alpha end,function(v)config.lines.alpha=v end)
  slider(p,"Line thickness",22,-150,1,120,1,function()return config.lines.size end,function(v)config.lines.size=v end)
  slider(p,"Line inset %",22,-188,0,45,1,function()return config.lines.inset end,function(v)config.lines.inset=v end)
  textLine(p,"Individual reference bars",353,-88,250)
  check(p,"Left bar",350,-110,function()return config.lines.edges.left end,function(v)config.lines.edges.left=v end)
  check(p,"Right bar",480,-110,function()return config.lines.edges.right end,function(v)config.lines.edges.right=v end)
  check(p,"Top bar",350,-144,function()return config.lines.edges.top end,function(v)config.lines.edges.top=v end)
  check(p,"Bottom bar",480,-144,function()return config.lines.edges.bottom end,function(v)config.lines.edges.bottom=v end)
  check(p,"Peripheral darkening",12,-245,function()return config.vignette.enabled end,function(v)config.vignette.enabled=v end,"Darkens screen edges to reduce peripheral visual flow. Can obscure objects near the edges.")
  slider(p,"Darkening",22,-287,0.05,0.8,0.05,function()return config.vignette.alpha end,function(v)config.vignette.alpha=v end)
  slider(p,"Edge width %",350,-290,5,40,1,function()return config.vignette.width end,function(v)config.vignette.width=v end)
  button(p,"White",350,-195,78,25,function()config.lines.color={1,1,1};refreshAll() end)
  button(p,"Cyan",433,-195,78,25,function()config.lines.color={0.45,0.9,1};refreshAll() end)
  button(p,"Amber",516,-195,88,25,function()config.lines.color={1,0.75,0.35};refreshAll() end)
  p=pages[4];title(p,"Movement Protection",-8)
  textLine(p,"Adds extra edge darkening while moving, or during mouse-look/turn events when detected.",16,-35,600)
  check(p,"Speed-based protection",12,-64,function()return config.movement.enabled end,function(v)config.movement.enabled=v end,"Uses available player speed data; no automatic action or camera manipulation.")
  slider(p,"Speed threshold",22,-110,1,20,1,function()return config.movement.threshold end,function(v)config.movement.threshold=v end)
  slider(p,"Extra darkening",22,-155,0.05,1.6,0.05,function()return config.movement.alpha end,function(v)config.movement.alpha=v end)
  check(p,"Turn/mouse-look protection",12,-208,function()return config.dynamic.enabled end,function(v)config.dynamic.enabled=v end,"Triggered only if the Forever client fires documented looking/turning events. Does not read actual camera rotation.")
  slider(p,"Turn protection",22,-254,0.05,1.6,0.05,function()return config.dynamic.alpha end,function(v)config.dynamic.alpha=v end)
  button(p,"Test darkening (5 sec)",22,-305,195,25,function()
    -- Preview exactly the configured strengths, without a forced minimum.
    -- Apply both strengths together as though moving and turning simultaneously.
    SV.testMotionRemaining=5
    SV.testMotionLevel=clamp((config.movement.alpha or 0)+(config.dynamic.alpha or 0),0,1.6)
    SV.testMotionBand=math.max(0,(config.movement.alpha or 0)-1,(config.dynamic.alpha or 0)-1)
    vignetteStrength=SV.testMotionLevel
    motionBandExcess=SV.testMotionBand
    previewNumber:SetText("5")
    previewFrame:Show()
    refreshVignette()
    report("Previewing configured movement + turn strengths for five seconds")
  end)
  textLine(p,"Strength 1.6 is scaled to display opacity; camera turning requires client events. /sv status",16,-345,610)
  p=pages[5];title(p,"Camera Options (experimental)",-8)
  textLine(p,"Individual client CVars are used only if present. Previous values are restored when disabled.",16,-35,600)
  check(p,"Enable camera controls",12,-62,function()return config.camera.enabled end,function(v)config.camera.enabled=v end,"Enables only camera options that you explicitly select below.")
  for i,o in ipairs(cameraOptions) do
    check(p,o.label,18,-101-(i-1)*48,function()return not not config.camera.settings[o.key] end,function(v)config.camera.settings[o.key]=v end,o.help)
    local state=safeCVarGet(o.cvar)
    local status=textLine(p,(state~=nil and state~="") and ("CVar: "..tostring(state)) or "Not detected",390,-120-(i-1)*48,210)
    local optionKey=o.key
    cameraStatusTexts[optionKey]=status
  end
  textLine(p,"Unsupported settings are never forced. Check your WoW camera options too.",16,-365,610)
  p=pages[6];title(p,"Profiles and Backup",-8)
  textLine(p,"Save named profiles and copy a backup. Beta SavedVariables may not reload reliably.",16,-35,600)
  -- Separate profile name input from the profile selector. Only existing profiles appear in the dropdown.
  local name=CreateFrame("EditBox",nil,p,"InputBoxTemplate");name:SetSize(175,25);name:SetPoint("TOPLEFT",p,"TOPLEFT",28,-70);name:SetAutoFocus(false);name:SetText(config.profile or "Default")
  textLine(p,"Name for saving:",22,-53,190)
  local selectedProfile=config.profiles[config.profile] and config.profile or nil
  local profileDrop=button(p,"Choose saved profile  v",220,-70,205,25,function() end)
  local popup=CreateFrame("Frame",nil,p,"BackdropTemplate")
  popup:SetSize(205,242);popup:SetPoint("TOPLEFT",profileDrop,"BOTTOMLEFT",0,-2)
  popup:SetFrameStrata("FULLSCREEN_DIALOG");popup:EnableMouse(true);panel(popup);popup:Hide()
  local offset=0
  local options={}
  local function getProfileNames()
    local names={}
    for k,v in pairs(config.profiles) do if type(k)=="string" and type(v)=="table" then names[#names+1]=k end end
    table.sort(names)
    return names
  end
  local function updateDrop()
    local names=getProfileNames()
    if selectedProfile and not config.profiles[selectedProfile] then selectedProfile=nil end
    profileDrop:SetText((selectedProfile or "Choose saved profile").."  v")
    offset=clamp(offset,0,math.max(0,#names-7))
    for i,b in ipairs(options) do
      local profileName=names[offset+i]
      if profileName then
        b:SetText(profileName);b:Show()
        b:SetScript("OnClick",function()
          selectedProfile=profileName;name:SetText(profileName);popup:Hide();updateDrop()
        end)
      else b:Hide() end
    end
  end
  for i=1,7 do options[i]=button(popup,"",8,-8-(i-1)*29,189,26,function() end) end
  local prev=button(popup,"Up",8,-213,92,23,function()offset=math.max(0,offset-7);updateDrop() end)
  local nextPage=button(popup,"Down",105,-213,92,23,function()offset=offset+7;updateDrop() end)
  profileDrop:SetScript("OnClick",function() if popup:IsShown() then popup:Hide() else updateDrop();popup:Show() end end)
  button(p,"Save profile",435,-70,100,25,function()
    local n=name:GetText();if n=="" then report("Enter a profile name first");return end
    config.profile=n;config.profiles[n]={dots=copy(config.dots),focus=copy(config.focus),lines=copy(config.lines),vignette=copy(config.vignette),movement=copy(config.movement),dynamic=copy(config.dynamic),camera=copy(config.camera)}
    selectedProfile=n;save();updateDrop();report("Saved profile: "..n)
  end)
  button(p,"Load selected",220,-103,125,25,function()
    local n=selectedProfile;local d=n and config.profiles[n]
    if not d then report("Choose a saved profile from the dropdown first");return end
    for k,v in pairs(d) do config[k]=copy(v) end;config.profile=n
    if type(config.lines.edges)~="table" then config.lines.edges=copy(defaults.lines.edges) end
    popup:Hide();refreshAll();report("Loaded profile: "..n..". Reopen settings to refresh displayed controls.")
    window:Hide();window=nil;makeWindow();window:Show()
  end)
  button(p,"Reset all",355,-103,100,25,function()
    for k,v in pairs(defaults) do if k~="profiles" then config[k]=copy(v) end end
    popup:Hide();refreshAll();report("Reset to defaults")
    window:Hide();window=nil;makeWindow();window:Show()
  end)
  updateDrop()
  local backup=CreateFrame("EditBox",nil,p,"InputBoxTemplate");backup:SetSize(580,25);backup:SetPoint("TOPLEFT",p,"TOPLEFT",30,-153);backup:SetAutoFocus(false)
  backup:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  textLine(p,"Portable backup string (copy/paste):",22,-127,530)
  local function encode(v)
    if type(v)=="number" then return string.format("%.5f",v) elseif type(v)=="boolean" then return tostring(v) elseif type(v)=="string" then return string.format("%q",v) elseif type(v)=="table" then
      local t={};for k,x in pairs(v) do if type(k)=="number" then t[#t+1]="["..k.."]="..encode(x) elseif type(k)=="string" then t[#t+1]="["..string.format("%q",k).."]="..encode(x) end end
      return "{"..table.concat(t,",").."}" end return "nil"
  end
  button(p,"Export backup",22,-189,135,25,function()
    -- A readable Lua table backup. Importing strings as executable Lua would be unsafe, so import uses only the supported compact token format below.
    local d=config.dots
    local parts={"SV1",tostring(d.count),tostring(d.size),string.format("%.2f",d.alpha),tostring(d.band),tostring(d.margin),d.enabled and "1" or "0",config.focus.enabled and "1" or "0",config.lines.enabled and "1" or "0",config.vignette.enabled and "1" or "0"}
    backup:SetText(table.concat(parts,"|"));backup:HighlightText();backup:SetFocus();report("Compact settings code exported (full profiles use SavedVariables).")
  end)
  button(p,"Import backup",170,-189,135,25,function()
    local s=backup:GetText();local fields={};for token in string.gmatch(s,"[^|]+") do fields[#fields+1]=token end
    if #fields~=10 or fields[1]~="SV1" then report("Invalid backup code");return end
    local n1,n2,n3,n4,n5=tonumber(fields[2]),tonumber(fields[3]),tonumber(fields[4]),tonumber(fields[5]),tonumber(fields[6])
    if not(n1 and n2 and n3 and n4 and n5) then report("Invalid numeric settings");return end
    config.dots.count=clamp(math.floor(n1),1,40);config.dots.size=clamp(n2,2,100);config.dots.alpha=clamp(n3,0.05,1)
    config.dots.band=clamp(n4,5,49);config.dots.margin=clamp(n5,0,30)
    config.dots.enabled=fields[7]=="1";config.focus.enabled=fields[8]=="1";config.lines.enabled=fields[9]=="1";config.vignette.enabled=fields[10]=="1"
    config.dots.points={};refreshAll();report("Imported compact settings; reopen options to update sliders")
  end)
  textLine(p,"The compact backup includes essential switches and dot sliders, not custom dot coordinates.",22,-236,590)
  textLine(p,"Full settings and profiles live in SavedVariables: SteadyViewDB.",22,-259,590)
  button(p,"Light",22,-303,125,25,function()config.focus.enabled=true;config.dots.enabled=true;config.vignette.enabled=false;config.lines.enabled=false;config.movement.enabled=false;config.dynamic.enabled=false;refreshAll() end)
  button(p,"Balanced",157,-303,125,25,function()config.focus.enabled=true;config.dots.enabled=true;config.vignette.enabled=true;config.vignette.alpha=0.2;config.movement.enabled=false;refreshAll() end)
  button(p,"Strong",292,-303,125,25,function()config.focus.enabled=true;config.dots.enabled=true;config.vignette.enabled=true;config.vignette.alpha=0.45;config.lines.enabled=true;refreshAll() end)
  textLine(p,"Presets are starting points, not medical recommendations. Stop playing if symptoms develop.",22,-349,595)
  showPage(1)
  window:Hide()
end
local function makeEditor()
  editor=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
  editor:SetSize(420,96);editor:SetPoint("TOP",UIParent,"TOP",0,-95);editor:SetFrameStrata("TOOLTIP")
  panel(editor)
  title(editor,"Dot Edit Mode",-8)
  textLine(editor,"Drag dots anywhere on screen. Lock positions when done.",12,-34,402)
  button(editor,"Lock positions",12,-58,120,25,function()dotDragEnabled=false;editor:Hide();refreshDots();save();report("Dot positions locked") end)
  button(editor,"Randomize",138,-58,95,25,function()randomize();refreshDots();save() end)
  button(editor,"Settings",240,-58,83,25,function()dotDragEnabled=false;editor:Hide();refreshDots();window:Show() end)
  button(editor,"Clear zones",330,-58,82,25,function()config.dots.protected={};save();report("Custom protection zones cleared") end)
  editor:Hide()
end
function SV:OpenEditor()
  if InCombatLockdown and InCombatLockdown() then report("Open edit mode outside combat");return end
  if not config.dots.enabled then config.dots.enabled=true end
  if not config.enabled then config.enabled=true end
  if window then window:Hide() end
  dotDragEnabled=true;editor:Show();refreshDots()
end
local moving,turning,looking=false,false,false
local function reportStatus()
  local speed=0;if type(GetUnitSpeed)=="function" then local ok,v=pcall(GetUnitSpeed,"player");if ok then speed=v or 0 end end
  report("dots="..tostring(config.dots.enabled).." | speed="..tostring(speed).." | threshold="..tostring(config.movement.threshold).." | moving="..tostring(moving).." | turning="..tostring(turning).." | looking="..tostring(looking).." | moveAlpha="..tostring(config.movement.alpha).." | turnAlpha="..tostring(config.dynamic.alpha))
  for _,o in ipairs(cameraOptions) do report(o.label..": "..tostring(cameraStatus[o.key] or "Not tested")) end
end
SLASH_STEADYVIEW1="/steadyview";SLASH_STEADYVIEW2="/sv"
SlashCmdList.STEADYVIEW=function(msg)
  msg=(msg or ""):lower():match("^%s*(.-)%s*$")
  if not config then report("Still initializing. Please try again after login.");return end
  if msg=="edit" then SV:OpenEditor()
  elseif msg=="random" then randomize();refreshDots();save()
  elseif msg=="on" then config.enabled=true;refreshAll();report("Enabled")
  elseif msg=="off" then config.enabled=false;refreshAll();report("Disabled")
  elseif msg=="status" then reportStatus()
  else if not window then makeWindow() end if window:IsShown() then window:Hide() else window:Show() end end
end
local lastMotion,elapsed=0,0
SV:SetScript("OnEvent",function(_,ev)
  if ev=="ADDON_LOADED" then return end
  if ev=="PLAYER_LOGIN" then
    if type(SteadyViewDB)~="table" then SteadyViewDB=copy(defaults) end
    config=merge(defaults,SteadyViewDB)
    if not (type(SteadyViewDB.lines)=="table" and type(SteadyViewDB.lines.edges)=="table") then
      local pos=config.lines.position
      config.lines.edges={left=(pos=="sides" or pos=="all"),right=(pos=="sides" or pos=="all"),top=(pos=="topbottom" or pos=="all"),bottom=(pos=="topbottom" or pos=="all")}
    end
    -- Some Forever clients do not expose Lua math.randomseed. Never abort loading.
    if type(math.randomseed)=="function" then
      local seed=731
      if type(GetServerTime)=="function" then
        local ok,value=pcall(GetServerTime)
        if ok and type(value)=="number" then seed=value end
      elseif type(GetTime)=="function" then
        local ok,value=pcall(GetTime)
        if ok and type(value)=="number" then seed=math.floor(value*1000) end
      end
      pcall(math.randomseed,seed)
    end
    if type(config.dots.points)~="table" then config.dots.points={} end
    if type(config.dots.protected)~="table" then config.dots.protected={} end
    if #config.dots.points~=config.dots.count then randomize() end
    makeEditor();refreshAll();report("Loaded. Type /steadyview for settings.")
  elseif ev=="PLAYER_STARTED_MOVING" then moving=true
  elseif ev=="PLAYER_STOPPED_MOVING" then moving=false
  elseif ev=="PLAYER_STARTED_TURNING" then turning=true
  elseif ev=="PLAYER_STOPPED_TURNING" then turning=false
  elseif ev=="PLAYER_STARTED_LOOKING" then looking=true
  elseif ev=="PLAYER_STOPPED_LOOKING" then looking=false
  elseif ev=="DISPLAY_SIZE_CHANGED" or ev=="UI_SCALE_CHANGED" then
    if config then refreshAll() end
  end
end)
SV:RegisterEvent("PLAYER_LOGIN");SV:RegisterEvent("PLAYER_STARTED_MOVING");SV:RegisterEvent("PLAYER_STOPPED_MOVING")
SV:RegisterEvent("PLAYER_STARTED_TURNING");SV:RegisterEvent("PLAYER_STOPPED_TURNING")
SV:RegisterEvent("PLAYER_STARTED_LOOKING");SV:RegisterEvent("PLAYER_STOPPED_LOOKING")
SV:RegisterEvent("DISPLAY_SIZE_CHANGED");SV:RegisterEvent("UI_SCALE_CHANGED")
SV:SetScript("OnUpdate",function(_,dt)
  if not config then return end
  -- Track real elapsed frame time so that five seconds means five seconds.
  if (SV.testMotionRemaining or 0)>0 then
    SV.testMotionRemaining=math.max(0,SV.testMotionRemaining-dt)
    if SV.testMotionRemaining>0 then
      previewNumber:SetText(tostring(math.ceil(SV.testMotionRemaining)))
    else
      previewNumber:SetText("0")
      previewFrame:Hide()
    end
  end
  elapsed=elapsed+dt
  if elapsed<0.1 then return end
  elapsed=0
  local target=0
  local desiredBandExcess=0
  local previewActive=(SV.testMotionRemaining or 0)>0
  if previewActive then
    target=SV.testMotionLevel or 0
    desiredBandExcess=SV.testMotionBand or 0
  end
  if not previewActive and config.enabled and config.movement.enabled then
    local speed=0
    local haveSpeed=false
    if type(GetUnitSpeed)=="function" then local ok,s=pcall(GetUnitSpeed,"player");if ok and type(s)=="number" then speed=s;haveSpeed=true end end
    if speed>=config.movement.threshold or (moving and (not haveSpeed or config.movement.threshold<=1)) then target=target+config.movement.alpha;desiredBandExcess=math.max(desiredBandExcess,config.movement.alpha-1) end
  end
  if not previewActive and config.enabled and config.dynamic.enabled and (turning or looking) then target=target+config.dynamic.alpha;desiredBandExcess=math.max(desiredBandExcess,config.dynamic.alpha-1) end
  target=clamp(target,0,1.6)
  local nextValue=vignetteStrength+(target-vignetteStrength)*clamp(0.1/math.max(config.dynamic.fade,0.1),0,1)
  local smoothing=clamp(0.1/math.max(config.dynamic.fade,0.1),0,1)
  local nextBand=motionBandExcess+(desiredBandExcess-motionBandExcess)*smoothing
  local changed=math.abs(nextValue-vignetteStrength)>0.002 or math.abs(nextBand-motionBandExcess)>0.002
  vignetteStrength=nextValue;motionBandExcess=nextBand
  if changed then refreshVignette() end
  SV._cameraTicker=(SV._cameraTicker or 0)+0.1
  if SV._cameraTicker>=0.5 then SV._cameraTicker=0; refreshCameraStatusTexts() end
end)