local _, F = ...
local function label(parent, text, x, y, width)
  local s=parent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  s:SetPoint('TOPLEFT',x,y); s:SetWidth(width); s:SetJustifyH('LEFT'); s:SetText(text); return s
end
local function button(parent,text,x,y,width,click)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
  b:SetSize(width,24); b:SetPoint('TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',click); return b
end
local function window(name,title,width,height)
  local w=CreateFrame('Frame',name,UIParent,'BasicFrameTemplateWithInset')
  w:SetSize(width,height); w:SetPoint('CENTER'); w:SetClampedToScreen(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag('LeftButton')
  w:SetFrameStrata('DIALOG'); w:SetToplevel(true)
  w:SetScript('OnDragStart',w.StartMoving); w:SetScript('OnDragStop',w.StopMovingOrSizing)
  w:SetScript('OnHide',function(self)
    if self.suppressReturn then return end
    local previous=self.returnTo; self.returnTo=nil
    if previous then
      F.currentWindow=previous; previous:Show(); previous:Raise()
      if previous==F.window and F.Refresh then F.Refresh()
      elseif previous==F.details and F.RefreshDetails then F.RefreshDetails() end
    end
  end)
  w.TitleText:SetText('|TInterface\\AddOns\\MobAuction\\Media\\Icon:18:18|t '..title)
  table.insert(UISpecialFrames,name); return w
end
local function present(w)
  if F.currentWindow~=w or not w:IsShown() then
    local oldReturn=w.returnTo
    w.returnTo=nil
    for _,key in ipairs({'settings','report','details','setup','window'}) do
      local other=F[key]
      if other and other~=w and other:IsShown() then
        if other.returnTo==w then other.returnTo=nil; w.returnTo=oldReturn
        elseif not w.returnTo then w.returnTo=other end
        other.suppressReturn=true; other:Hide(); other.suppressReturn=nil
      end
    end
  end
  F.currentWindow=w; w:Show(); w:Raise()
end
local function dismissReport()
  if F.report then F.report.returnTo=nil; F.report:Hide() end
end
local function edit(parent,x,y,width)
  local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); e:SetSize(width,24)
  e:SetPoint('TOPLEFT',x,y); e:SetAutoFocus(false); e:SetNumeric(true); e:SetMaxLetters(4); return e
end
local function setupSkillStatus(id,row)
  local value=tonumber(row.input:GetText())
  local detected=F.db.detectedSkills[id]
  local automatic=value==nil or value==detected
  row.status:SetText((automatic and 'Automatic' or ('Preview '..value))..' | detected '..(detected or '?'))
end
function F.ShowSetup()
  F.DiscoverProfessions()
  if not F.setup then
    local ids=F.ProfessionIDs()
    local w=window('MobAuctionSetup','MobAuction - Your character',690,160+math.ceil(#ids/2)*38)
    F.setup=w; F.setupRows={}
    label(w,'Which professions does this character have? Select each and enter its skill level.',18,-40,650)
    label(w,'Detected ranks follow skill gains. Enter a different rank to preview it; blank restores automatic.',18,-59,650)
    for i,id in ipairs(ids) do
      local x=20+((i-1)%2)*330; local y=-92-math.floor((i-1)/2)*38
      local check=CreateFrame('CheckButton',nil,w,'UICheckButtonTemplate'); check:SetSize(24,24); check:SetPoint('TOPLEFT',x,y)
      label(w,F.professions[id],x+28,y-1,195)
      local input=edit(w,x+235,y,65)
      input:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
      local row={check=check,input=input,status=label(w,'',x+28,y-17,195)}
      F.setupRows[id]=row
      input:SetScript('OnTextChanged',function() setupSkillStatus(id,row) end)
    end
    local y=-100-math.ceil(#ids/2)*38
    button(w,'Detect my professions',18,y,185,function()
      local found=F.DiscoverProfessions(); local count=0
      for id,row in pairs(F.setupRows) do
        row.check:SetChecked(found[id]~=nil); row.input:SetText(found[id] and tostring(found[id]) or '')
        setupSkillStatus(id,row)
        if found[id] then count=count+1 end
      end
      F.setupStatus:SetText(count>0 and 'Detected. Review and save; open each crafting profession once to import recipes.' or 'No professions returned. Select them manually or open a profession window and retry.')
    end)
    F.setupUseDetected=button(w,'Use detected levels',215,y,185,function()
      local selected={}; for id,row in pairs(F.setupRows) do selected[id]=row.check:GetChecked() end
      local _,available,found=F.UseDetectedLevels(selected)
      for id,row in pairs(F.setupRows) do
        if selected[id] and found[id] then row.input:SetText(tostring(found[id])) end
        setupSkillStatus(id,row)
      end
      F.setupStatus:SetText(available>0 and 'Selected detected professions now follow skill gains. Save character to keep your selections.' or 'No selected professions detected. Open the profession or click Detect my professions, then retry.')
      F.Refresh()
    end)
    button(w,'Save character',490,y,170,function()
      local selected,levels={},{}
      for id,row in pairs(F.setupRows) do selected[id]=row.check:GetChecked(); levels[id]=row.input:GetText() end
      local ok,err=F.SaveSetup(selected,levels)
      if not ok then F.setupStatus:SetText(err); return end
      w:Hide(); F.Open()
    end)
    F.setupStatus=label(w,'',18,y-32,650)
  end
  for id,row in pairs(F.setupRows) do
    row.check:SetChecked(F.db.selectedProfessions[id] or false)
    local level=F.SkillLevel(id); row.input:SetText(level and tostring(level) or '')
    setupSkillStatus(id,row)
  end
  present(F.setup)
end
local function recipeTooltip(row)
  local r=row.result; if not r then return end
  GameTooltip:SetOwner(row,'ANCHOR_RIGHT'); GameTooltip:AddLine(r.recipe.name,1,.8,.3)
  GameTooltip:AddLine((F.professions[r.recipe.profession] or 'Profession')..' | '..(r.recipe.learned==true and 'Known' or (r.recipe.learned==false and 'Unlearned' or 'Learning status unknown')))
  local rank,source=F.RequiredSkill(r.recipe)
  GameTooltip:AddLine('Minimum skill: '..(rank or '?')..' - '..source,.8,.8,.8,true)
  if r.recipe.databaseReference then
    GameTooltip:AddLine('Recipe Registry reference, build '..tostring(r.recipe.sourceBuild or '?')..'; recipe details need confirmation.',1,.8,.3,true)
    if r.recipe.databaseRequiredSkill then GameTooltip:AddLine('Database skill requirement: '..r.recipe.databaseRequiredSkill..' (unverified)',.8,.8,.8,true) end
  end
  for _,line in ipairs(r.lines) do
    GameTooltip:AddDoubleLine(line.quantity..' x '..(F.ItemName(line.itemID) or tostring(line.itemID)),F.Money(line.price))
    GameTooltip:AddLine(line.source or 'Unknown',.7,.7,.7,true)
  end
  GameTooltip:AddDoubleLine('Sale forecast',F.Money(r.value)); GameTooltip:AddDoubleLine('Auction fee',F.Money(r.fee))
  GameTooltip:AddDoubleLine('Deposit at risk',F.Money(r.deposit)); GameTooltip:AddLine(r.depositSource or '',.7,.7,.7,true)
  if r.acquisition then
    GameTooltip:AddDoubleLine(r.acquisition=='auction' and 'Recipe purchase price' or (r.acquisition=='catalogue' and 'Learning price unknown' or 'Trainer price'),F.Money(r.acquisitionPrice))
    GameTooltip:AddLine(r.acquisitionPriceSource or '',.7,.7,.7,true)
    GameTooltip:AddLine('Learning price is separate; it does not reduce craft profit.',1,.8,.3,true)
    if r.status then GameTooltip:AddLine(r.status,1,.8,.3,true) end
    if r.demandPerDay then GameTooltip:AddLine(string.format('AHledger estimates %.1f units sold per day across the market; your sales are not guaranteed.',r.demandPerDay),.8,.8,.8,true) end
    for _,reason in ipairs(r.pending or {}) do GameTooltip:AddLine(reason,1,.8,.3,true) end
  end
  for _,m in ipairs(r.missing) do GameTooltip:AddLine(m,1,.4,.3,true) end
  GameTooltip:AddLine('Click to check ingredient listings. Sale proceeds remain estimates.',.8,.8,.8,true)
  GameTooltip:Show()
end
function F.Refresh()
  if not F.window then return end
  if F.activeTab=='farms' then F.RefreshFarms(); return end
  local term,terms=F.RecipeTerm(F.filter),F.RecipeTerm(F.filter,true)
  F.recipeHeader:SetText(term:sub(1,1):upper()..term:sub(2))
  F.recipeHint:SetText((F.worthLearning and 'Highest sale profit first. Recipe price is separate.' or 'Highest sale profit first. Click a '..term..'; mouse wheel scrolls.'))
  F.results=F.worthLearning and F.WorthLearning() or F.Results()
  F.page=math.max(1,math.min(F.page or 1,math.max(1,math.ceil(#F.results/10))))
  for i,row in ipairs(F.rows) do
    local r=F.results[(F.page-1)*10+i]; row.result=r
    if r then
      row:Show(); local profit=r.adjusted
      local color=r.estimated and '|cffffcc55' or (profit and profit>0 and '|cff55ee88' or '|cffbbbbbb')
      local displayedCost=r.materialsComplete and r.cost or nil
      if F.worthLearning then displayedCost=r.acquisitionPrice end
      row.fields[1]:SetText(r.acquisition=='auction' and r.acquisitionName or r.recipe.name)
      row.fields[2]:SetText(F.Money(displayedCost))
      row.fields[3]:SetText(F.worthLearning and (color..F.Money(profit)..'|r') or F.Money(r.profit))
      row.fields[4]:SetText(F.Money(r.deposit))
      row.fields[5]:SetText(F.worthLearning and F.Money(r.profit) or (color..F.Money(profit)..'|r'))
      local learningStatus=r.candidate and 'Worth learning' or (r.flag=='profit_candidate' and 'Profit candidate'
        or (r.flag=='not_profitable' and 'No profit' or (r.acquisition=='trainer' and 'Trainer' or (r.recipe.problem and 'Need craft data' or (r.estimated and 'Forecast' or (r.needsDeposit and 'Need deposit' or 'Needs checks'))))))
      row.fields[6]:SetText(F.worthLearning and learningStatus or (#r.missing>0 and 'Needs prices' or (r.needsDeposit and 'Need deposit' or (r.estimated and 'Estimate' or 'Costs checked'))))
    else row:Hide() end
  end
  local c=F.Coverage()
  F.status:SetText(string.format('%d results | page %d/%d | %d craft%s | cut %g%% | %d failed listings',#F.results,F.page,math.max(1,math.ceil(#F.results/10)),F.worthLearning and 1 or F.db.crafts,(not F.worthLearning and F.db.crafts~=1) and 's' or '',F.db.cut,F.db.failures))
  local referenceRows=0
  for _,r in ipairs(F.results) do if r.acquisition=='catalogue' or (not F.worthLearning and r.recipe.knowledgeVerified) then referenceRows=referenceRows+1 end end
  local coverage=F.worthLearning and F.AuctionLearningStatus and F.AuctionLearningStatus():match('^[^\n]+') or string.format('Imported: %d known / %d unlearned. Minimum skill verified or confirmed: %d; unknown: %d.',c.known,c.unlearned,c.verified,c.unknown)
  if referenceRows>0 then coverage=coverage..' | '..referenceRows..' catalogue results.' end
  F.coverageLabel:SetText(coverage)
  F.skillLabel:SetText(F.SkillStatusSummary())
  F.professionButton:SetText(F.filter and F.professions[F.filter] or 'All my professions')
  F.modeButton:SetText(F.worthLearning and 'Worth Learning: ON' or 'Worth Learning')
  if F.scanButton then F.scanButton:SetText('Full AH scan') end
  F.costButton:SetText(F.worthLearning and (F.learningOnlyAH and 'Learning: AH recipes' or 'Learning: all sources') or (F.db.strictCosts and 'Pricing: checked listings' or 'Pricing: scan estimates'))
  if F.scanStatusLabel then
    local status=F.FullScanStatus and F.FullScanStatus() or 'Full AH scan has not run yet.'
    F.scanStatusLabel:SetText(#status>140 and status:sub(1,137)..'...' or status)
  end
  if F.moreRecipesButton then F.moreRecipesButton:SetShown(F.worthLearning==true) end
  if F.craftAmountControls then for _,control in ipairs(F.craftAmountControls) do control:SetShown(not F.worthLearning) end end
  F.empty:SetShown(#F.results==0)
  local emptyText=F.ScanStatus()
  if F.excluded and (F.excluded.unknown or 0)>0 then emptyText=emptyText..'\nSome known '..terms..' need skill evidence. Click Use detected levels, or reopen the profession to update its saved '..terms..' automatically.' end
  if F.excluded and (F.excluded.unlearned or 0)>0 then emptyText=emptyText..'\nCrafting shows learned '..terms..'. Use Catalogue to inspect unlearned '..terms..'.' end
  F.empty:SetText(F.worthLearning and F.LearningStatus() or emptyText)
  F.materialHeader:SetText(F.worthLearning and 'Learn price' or 'Materials')
  F.saleHeader:SetText(F.worthLearning and 'Profit / craft' or 'Sale profit')
  F.profitHeader:SetText(F.worthLearning and 'Sale profit' or 'Adjusted profit')
end
function F.RefreshRecipes()
  local previous=F.db.lastImportAttempt
  local count=F.ReadRecipes()
  F.Refresh()
  local attempt=F.db.lastImportAttempt
  if attempt and attempt~=previous and attempt.why then F.Say(attempt.why)
  else
    F.Say('Using saved '..F.RecipeTerm(F.filter,true)..'. Open '..(F.filter and F.professions[F.filter] or 'your crafting profession')..' in WoW to import new entries automatically.')
  end
  return count
end
function F.Open()
  dismissReport()
  for _,key in ipairs({'details','settings','setup'}) do if F[key] then F[key].returnTo=nil; F[key]:Hide() end end
  if not F.db.setupComplete then F.ShowSetup(); return end
  if F.window then present(F.window); F.Refresh(); return end
  local main=window('MobAuctionWindow','MobAuction - Crafting opportunities',950,630); F.window=main
  F.craftTab=button(main,'Crafting',18,-35,130,function() F.ShowTab('crafting') end)
  F.farmTab=button(main,'Recommended Farms',155,-35,185,function() F.ShowTab('farms') end)
  button(main,'Fees & settings',350,-35,145,function() F.ShowSettings() end)
  button(main,'Help & status',505,-35,130,function() F.ShowHelp() end)
  label(main,'v'..F.VERSION,855,-42,75)
  local w=CreateFrame('Frame',nil,main); w:SetSize(950,595); w:SetPoint('TOPLEFT',0,-34); F.craftPanel=w
  local function scrollResults(_,delta)
    if delta==0 then return end
    F.page=(F.page or 1)+(delta<0 and 1 or -1); F.Refresh()
  end
  w:EnableMouseWheel(true); w:SetScript('OnMouseWheel',scrollResults)
  F.professionButton=button(w,'All my professions',18,-38,180,function()
    local ids={}; for _,id in ipairs(F.ProfessionIDs()) do if F.db.selectedProfessions[id] then ids[#ids+1]=id end end
    local nextID=ids[1]
    if F.filter then nextID=nil; for i,id in ipairs(ids) do if id==F.filter then nextID=ids[i+1]; break end end end
    F.filter=nextID; F.page=1; F.Refresh()
  end)
  button(w,'Character setup',205,-38,130,F.ShowSetup)
  F.scanButton=button(w,'Full AH scan',342,-38,100,F.Scan)
  button(w,'Refresh',449,-38,90,F.RefreshRecipes)
  F.modeButton=button(w,'Worth Learning',546,-38,165,function()
    F.worthLearning=not F.worthLearning
    -- The most useful view at an auctioneer is also bounded by the number of
    -- recipe items actually listed. All known sources remain one click away.
    if F.worthLearning and F.learningOnlyAH==nil then F.learningOnlyAH=true end
    F.page=1
    F.Refresh()
  end)
  button(w,'Recipe deals',718,-38,100,function() F.ShowDeals() end)
  button(w,'Catalogue',825,-38,105,function() F.ShowCatalogue() end)
  F.costButton=button(w,'',18,-73,185,function()
    if F.worthLearning then F.learningOnlyAH=not F.learningOnlyAH; F.page=1; F.Refresh()
    else F.db.strictCosts=not F.db.strictCosts; F.Refresh() end
  end)
  F.moreRecipesButton=button(w,'Scan status',220,-73,190,function() F.ShowHelp() end)
  local craftsLabel=label(w,'Crafts',220,-80,45); local amount=edit(w,265,-73,65); amount:SetText(tostring(F.db.crafts))
  local applyCrafts=button(w,'Apply',340,-73,70,function()
    local n=tonumber(amount:GetText())
    if n and n>=1 and n<=1000 and n==math.floor(n) then F.db.crafts=n; amount:ClearFocus(); F.Refresh() else F.Say('Enter 1 to 1000 crafts.') end
  end)
  F.craftAmountControls={craftsLabel,amount,applyCrafts}
  F.recipeHint=label(w,'',430,-80,490)
  local positions,widths={10,285,420,555,675,805},{270,130,130,115,125,110}
  local headings={'Recipe','Materials','Sale profit','Deposit','Adjusted profit','Evidence'}
  for i,title in ipairs(headings) do
    local h=label(w,title,positions[i]+10,-112,widths[i])
    if i==1 then F.recipeHeader=h elseif i==2 then F.materialHeader=h elseif i==3 then F.saleHeader=h elseif i==5 then F.profitHeader=h end
  end
  F.rows={}
  for i=1,10 do
    local row=CreateFrame('Button',nil,w); row:SetSize(925,29); row:SetPoint('TOPLEFT',10,-135-(i-1)*29)
    row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight'); row.fields={}
    row:EnableMouseWheel(true); row:SetScript('OnMouseWheel',scrollResults)
    for j=1,6 do row.fields[j]=label(row,'',positions[j],-5,widths[j]) end
    row:SetScript('OnEnter',recipeTooltip); row:SetScript('OnLeave',function() GameTooltip:Hide() end)
    row:SetScript('OnClick',function() if row.result then F.ShowDetails(row.result.recipe,row.result.acquisitionItemID,row.result.acquisition) end end)
    F.rows[i]=row
  end
  F.empty=label(w,'',30,-145,885)
  button(w,'< Previous',18,-437,100,function() F.page=(F.page or 1)-1; F.Refresh() end)
  button(w,'Next >',125,-437,100,function() F.page=(F.page or 1)+1; F.Refresh() end)
  F.status=label(w,'',245,-443,680)
  F.coverageLabel=label(w,'',18,-478,910)
  F.skillLabel=label(w,'',18,-502,715)
  F.useDetectedButton=button(w,'Use detected levels',750,-495,175,function()
    local changed,available=F.UseDetectedLevels()
    F.Refresh()
    if available==0 then F.Say('No selected professions detected. Open a profession, then retry Use detected levels.')
    elseif changed>0 then F.Say('Selected detected professions now follow your current skill levels.') end
  end)
  F.scanStatusLabel=label(w,'',18,-526,910)
  F.scanStatusLabel:SetHeight(18)
  F.scanStatusLabel:SetWordWrap(false)
  label(w,'Full scan prices are forecasts. Check ingredients before buying; detailed quotes expire after 60 seconds.',18,-550,910)
  present(main); F.Refresh()
end
function F.ShowDetails(recipe,learningItemID,learningSource)
  if not F.details then
    local w=window('MobAuctionDetails','MobAuction - Batch check',720,590); F.details=w
    F.detailTitle=label(w,'',18,-40,680)
    label(w,'Finish other AH scans first. Check each ingredient; click again to request missing pages.',18,-65,680)
    local scroll=CreateFrame('ScrollFrame',nil,w,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',18,-96); scroll:SetSize(655,315)
    local content=CreateFrame('Frame',nil,scroll); content:SetSize(655,315); scroll:SetScrollChild(content)
    F.detailContent=content; F.detailRows={}
    F.detailSummary=label(w,'',18,-431,680)
    F.bestBatchButton=button(w,'Best batch (1-100)',18,-530,160,function()
      local best,count,limited=F.PlanBatch(F.detailRecipe)
      F.Say(best and ('Best of '..count..' fully priced batches: '..best.crafts..' crafts, forecast profit '..F.Money(best.adjusted)..'. Recheck before buying.') or 'No supported profitable batch. Check costs, deposits and sale prices first.')
      if limited then F.Say('Stopped at the calculation limit to keep the game responsive. Larger batches were not compared.') end
    end)
    button(w,'Refresh costs',190,-530,130,F.RefreshDetails)
    button(w,'Back',335,-530,85,function() w:Hide() end)
  end
  F.detailRecipe=recipe; F.detailLearningItemID=learningItemID
  F.detailLearningSource=learningSource
  F.detailLearningMode=learningSource~=nil or learningItemID~=nil
  present(F.details); F.RefreshDetails()
end
function F.RefreshDetails()
  if not F.details or not F.detailRecipe then return end
  F.priceCache={}
  local recipe
  if F.detailRecipe.referenceOnly and F.CatalogueRecipes then
    recipe=F.CatalogueRecipes()[F.detailRecipe.id] or F.detailRecipe
  else recipe=F.db.recipes[F.detailRecipe.id] or F.detailRecipe end
  F.detailRecipe=recipe
  local learning=F.detailLearningItemID and F.EvaluateAuctionLearning and F.EvaluateAuctionLearning(F.detailLearningItemID)
  if F.detailLearningSource=='catalogue' and F.EvaluateCatalogueLearning then learning=F.EvaluateCatalogueLearning(recipe.id) end
  if learning and learning.recipe then recipe=learning.recipe; F.detailRecipe=recipe end
  local settings=F.db
  if F.detailLearningMode then settings={}; for key,value in pairs(F.db) do settings[key]=value end; settings.crafts=1 end
  local r=learning or F.Evaluate(recipe,settings,F.Quote,F.Deposit)
  F.detailTitle:SetText(recipe.name..' | '..settings.crafts..' craft'..(settings.crafts==1 and '' or 's')..' | '..F.RecipeTerm(recipe.profession)..' ID '..recipe.id)
  F.bestBatchButton:SetShown(not F.detailLearningMode)
  local lines={}
  if F.detailLearningItemID then
    lines[#lines+1]={itemID=F.detailLearningItemID,quantity=1,price=learning and learning.acquisitionPrice,
      source=learning and learning.acquisitionPriceSource or 'Recipe listing unavailable; scan recipes again',purchase=true}
  end
  for _,line in ipairs(r.lines) do lines[#lines+1]=line end
  for _,row in ipairs(F.detailRows) do row:Hide() end
  for i,line in ipairs(lines) do
    local row=F.detailRows[i]
    if not row then
      row=CreateFrame('Frame',nil,F.detailContent); row:SetSize(650,45); row:SetPoint('TOPLEFT',0,-(i-1)*45)
      row.text=label(row,'',0,0,515)
      row.check=button(row,'Check',540,0,90,function() F.RequestDepth(row.itemID) end)
      F.detailRows[i]=row
    end
    row.itemID=line.itemID; row:Show()
    row.text:SetText(line.quantity..' x '..(F.ItemName(line.itemID) or ('Item '..line.itemID))..'  '..F.Money(line.price)..'\n'..(line.purchase and 'Recipe price (separate): ' or '')..(line.source or 'Unknown'))
  end
  F.detailContent:SetHeight(math.max(315,#lines*45))
  local why=#r.missing>0 and table.concat(r.missing,', ') or (r.needsDeposit and r.depositSource or 'Sale price is a forecast; checked listings can change.')
  local summary='Materials: '..F.Money(r.materialsComplete and r.cost or nil)..' | Sale profit: '..F.Money(r.profit)..' | After failed listings: '..F.Money(r.adjusted)..'\nDeposit: '..F.Money(r.deposit)..' | '..(why or 'Unknown')
  if F.detailLearningItemID then
    summary=summary..'\nRecipe price: '..F.Money(learning and learning.acquisitionPrice)..' (excluded from profit). '
      ..(learning and (learning.candidate and 'Worth learning.' or learning.status or '') or 'Run Full AH scan to refresh this listing.')
    if learning and #(learning.pending or {})>0 then summary=summary..'\n'..table.concat(learning.pending,'; ')
    elseif learning and learning.demandPerDay then summary=summary..string.format(' Estimated market sales: %.1f units/day.',learning.demandPerDay) end
  elseif F.detailLearningSource=='catalogue' then
    summary=summary..'\n'..(learning and learning.status or 'Research recipe: check how to obtain it and its learning requirements.')
  elseif F.detailLearningMode then
    summary=summary..'\nTrainer price: '..F.Money(recipe.trainingCost)..' (excluded from profit). Trainer: '..(recipe.trainerName or '?')
  end
  F.detailSummary:SetText(summary)
end
-- Scrollable text report used for recipe coverage and deal explanations.
local report
report=function(title,lines,actions,page,profession)
  if not F.report then
    local w=window('MobAuctionReport','MobAuction',780,580); F.report=w
    button(w,'Back',18,-535,100,function() w:Hide() end)
    F.reportPrevious=button(w,'< Previous',145,-535,100,function()
      local d=F.reportData; report(d.title,d.lines,d.actions,d.page-1,d.profession)
    end)
    F.reportNext=button(w,'Next >',255,-535,100,function()
      local d=F.reportData; report(d.title,d.lines,d.actions,d.page+1,d.profession)
    end)
    F.reportPage=label(w,'',380,-542,330)
    local scroll=CreateFrame('ScrollFrame',nil,w,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',18,-40); scroll:SetSize(720,470)
    F.reportScroll=scroll
    local content=CreateFrame('Frame',nil,scroll); content:SetSize(720,470); scroll:SetScrollChild(content)
    F.reportContent=content; F.reportText=label(content,'',0,0,710)
    F.reportRows={}
  end
  page=math.max(1,math.min(page or 1,math.max(1,math.ceil(#(actions or {})/20))))
  F.reportData={title=title,lines=lines,actions=actions,page=page,profession=profession}
  F.report.TitleText:SetText(title); F.reportText:SetText(table.concat(lines,'\n\n'))
  local height=F.reportText:GetStringHeight()+20
  for _,row in ipairs(F.reportRows) do row:Hide() end
  for i=1,math.min(20,#(actions or {})-(page-1)*20) do
    local action=actions[(page-1)*20+i]
    local row=F.reportRows[i]
    if not row then
      row=CreateFrame('Button',nil,F.reportContent); row:SetWidth(700)
      row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
      row.text=label(row,'',6,-6,680)
      row:SetScript('OnClick',function(self) if self.action then self.action.click() end end)
      F.reportRows[i]=row
    end
    row.action=action; row.text:SetText(action.label)
    local rowHeight=math.max(52,row.text:GetStringHeight()+16)
    row:ClearAllPoints(); row:SetPoint('TOPLEFT',0,-height); row:SetHeight(rowHeight); row:Show()
    height=height+rowHeight+5
  end
  F.reportPrevious:SetShown(actions~=nil); F.reportNext:SetShown(actions~=nil)
  F.reportPage:SetText(actions and string.format('%d %s | page %d/%d',#actions,F.RecipeTerm(profession,#actions~=1),page,math.max(1,math.ceil(#actions/20))) or '')
  F.reportContent:SetHeight(math.max(470,height)); F.reportScroll:SetVerticalScroll(0)
  present(F.report)
end
function F.ShowSettings()
  if not F.settings then
    local w=window('MobAuctionSettings','MobAuction - Fees and pricing',620,395); F.settings=w; F.settingFields={}
    label(w,'These assumptions change every profit forecast. Confirm the cut for the AH you use.',18,-42,580)
    local rows={{'cut','Auction cut (%)'},{'duration','Listing duration (1 short, 2 medium, 3 long)'},
      {'failures','Failed listings before one successful sale'},{'maxAge','Maximum price age (days)'}}
    for i,row in ipairs(rows) do
      label(w,row[2],20,-82-(i-1)*38,430)
      F.settingFields[row[1]]=edit(w,480,-75-(i-1)*38,80)
    end
    F.depositModeButton=button(w,'',20,-225,550,function()
      F.db.assumedDeposit=F.db.assumedDeposit==false and 100 or false
      F.depositModeButton:SetText(F.db.assumedDeposit==false and 'Deposit: game quote (click to assume 1s / item)' or 'Deposit: assumed 1s / item (click for game quote)')
      F.Refresh(); F.RefreshDetails()
    end)
    F.settingsStatus=label(w,'',20,-278,575)
    button(w,'Save settings',430,-305,150,function()
      local values={}; for key,input in pairs(F.settingFields) do values[key]=input:GetText() end
      local ok,why=F.SavePricingSettings(values)
      if not ok then F.settingsStatus:SetText(why); return end
      w:Hide(); F.Refresh(); F.RefreshDetails()
    end)
    button(w,'Back',20,-305,100,function() w:Hide() end)
  end
  for key,input in pairs(F.settingFields) do input:SetText(tostring(F.db[key])) end
  F.depositModeButton:SetText(F.db.assumedDeposit==false and 'Deposit: game quote (click to assume 1s / item)' or 'Deposit: assumed 1s / item (click for game quote)')
  F.settingsStatus:SetText(''); present(F.settings)
end
function F.ShowHelp()
  local api=C_TradeSkillUI
  local lines={
    'MobAuction '..F.VERSION..' | Game build '..F.Build(),
    '1. Character setup: Detect your professions, review the selections, and Save. Use detected levels removes manual skill previews.\n2. Open each crafting profession. Plans and recipes import automatically as they load. Expand groups in older profession windows.\n3. Open the AH and click Full AH scan. Keep the auction house open until it finishes. One snapshot covers materials, crafted items and recipe listings.\n4. Review Crafting or Worth Learning. Click a result and Check each ingredient before buying to verify current stock and batch costs.',
    'Pricing: checked listings needs recent quantity results (60 seconds). Pricing: scan estimates can preview costs from recent unit prices, but does not verify stock. A ? means missing information, never a free ingredient.',
    'Crafting opportunities are sorted by highest Sale profit for the selected batch size; unknown profits come last. Sale profit subtracts materials and the AH cut. The deposit is refunded on a sale; Adjusted profit also subtracts deposits lost on expected failed listings.',
    'Worth Learning sorts by Sale profit for one craft; Profit / craft also shows expected failed deposit losses. Learn price is shown separately and never deducted from profit or used for ranking. Learning: all sources includes catalogue research and trainer observations; Learning: AH recipes shows recipe items offered in your scan. Missing crafting data or learning requirements remain marked for checking. Strong Worth learning flags require a usable unlearned recipe, checked profit and recent estimated market demand. Profit alone cannot guarantee a sale.',
    F.FullScanStatus and F.FullScanStatus() or 'Full AH scan unavailable.',
    'Full scans use the server snapshot API, with a shared cooldown of about 15 minutes. Completed Auctionator scans can supply the same snapshot. Incomplete scans preserve the previous completed prices. Minimum asking prices are forecasts; other buyers, stack sizes and price tiers can change what you actually pay.',
    F.CatalogueStatusText and F.CatalogueStatusText() or 'Reference catalogue unavailable.',
    'Fees & settings controls AH cut, listing duration, expected failed listings and price age. Output prices are forecasts. Owned ingredients still have their purchase/replacement value.',
    F.ScanStatus(),
    'Auction house: '..(F.IsAuctionHouseOpen() and 'open; scans and ingredient checks can run.' or 'closed; talk to an auctioneer and keep the auction window open.'),
    'Profession reader: '..((api and api.GetRecipeSchematic) and 'modern API available; legacy fallback also enabled.' or 'legacy windows; imports the learned recipes they expose.'),
    F.LearningStatus(),
    'Recommended Farms uses recent prices plus Questie/QuestieDB locations and historical drop references. It is a comparison of loot values, not measured gold per hour. Unknown levels and rates stay unknown.',
    'Recipe deals only checks listings you browse, using AHledger historical prices. It does not confirm that you can learn the recipe or that it will resell.',
    'Close a detail/report/settings window with Back, X or Escape to return. /moba always returns to the main page. No button buys, crafts, trains or posts anything.'}
  report('MobAuction - Help and status',lines)
end
function F.ShowCatalogue()
  F.ReadRecipes()
  if F.RefreshCatalogue then F.RefreshCatalogue('profession') end
  local term,terms=F.RecipeTerm(F.filter),F.RecipeTerm(F.filter,true)
  local lines={F.ScanStatus(),'Click a '..term..' below to check its ingredients. Legacy windows import visible learned '..terms..'; expand their groups first. Imports stay saved after closing the profession window. Unknown minimum skill does not block a known '..term..' at its observed rank.'}
  if F.CatalogueStatusText then lines[#lines+1]=F.CatalogueStatusText() end
  local all={}; for id,r in pairs(F.db.recipes) do all[id]=r end
  for id,r in pairs(F.CatalogueRecipes and F.CatalogueRecipes() or {}) do
    if not all[id] or all[id].importNeedsRefresh or all[id].problem or all[id].observedBuild~=F.Build() or r.knowledgeVerified then all[id]=r end
  end
  local recipes={}; for _,r in pairs(all) do if F.db.selectedProfessions[r.profession] and (not F.filter or r.profession==F.filter) then recipes[#recipes+1]=r end end
  table.sort(recipes,function(a,b) return a.name<b.name end)
  local actions={}
  local reasons={profession='Outside selected professions',stale='Reopen profession to update its saved '..term..' data automatically',unsupported='Unsupported output or ingredients',unlearned='Not learned / training unavailable',above='Above selected skill',unknown='Need skill evidence; reopen profession or restore automatic skill'}
  for _,r in ipairs(recipes) do
    local rank,source=F.RequiredSkill(r); local _,reason=F.Eligible(r)
    local recipe=r
    local state=r.importNeedsRefresh and 'Older import needs repair' or (r.learned==true and 'Known' or (r.learned==false and 'Unlearned' or 'Learning status unknown'))
    local explanation=r.databaseReference and 'Reference database forecast; confirm ingredients and learning requirements in game.' or (r.importNeedsRefresh and 'Profession label is unverified. Reopen the actual crafting profession to update it automatically.' or r.problem or reasons[reason] or 'Ready to compare costs')
    actions[#actions+1]={label=string.format('%s - %s\nMinimum skill %s (%s). %s',r.name,state,rank or '?',source,explanation),click=function() F.ShowDetails(recipe,nil,recipe.referenceOnly and recipe.learned~=true and 'catalogue' or nil) end}
  end
  local title=F.filter and ((F.professions[F.filter] or 'Profession')..' '..term..' catalogue') or 'Recipe catalogue'
  report('MobAuction - '..title,lines,actions,nil,F.filter)
end
function F.ShowDeals()
  local lines={'Recipe bargain candidates for ALL professions. Historical asking prices are not sale guarantees.\nDefault: at least 40% below a 7-day/30-day median and 10s saved. Availability and learning requirements need checking.'}
  for _,d in ipairs(F.DealList()) do lines[#lines+1]=string.format('%s [%d]%s\nListed %s | Reference %s | %.0f%% below | Saving %s\nObserved %ds ago. Search this item at the AH to inspect it.',d.name,d.id,d.matches and ' - Matches your professions' or '',F.Money(d.price),F.Money(d.reference),d.discount,F.Money(d.saving),time()-d.seen) end
  if #lines==1 then lines[#lines+1]='No current candidates. Browse recipe items at the AH with AHledger enabled for historical prices. Alerts only cover listings you view/search.' end
  report('MobAuction - Recipe deals',lines)
end
function F.ShowFarmDetails(r)
  local best=r.best
  local deposit,depositSource=F.Deposit(r.id,1,F.db.duration)
  local lines={r.name..' ['..r.id..']',
    'Recent asking price: '..F.Money(r.price)..' per item ('..r.priceSource..'). After '..F.db.cut..'% AH cut: '..F.Money(r.net)..'.',
    'Suggested minimum level for the listed farm: '..(r.level or 'Unknown')..'. This is the highest creature level at that source, not a hard game requirement or a guarantee of easy combat.',
    'Reference model per 100 kills: '..F.Money(r.score)..'. Assumes one item per successful drop and a sale at the asking price. Before deposit losses, travel, repairs and other costs. No gold/hour or sell-through estimate is available.',
    'Deposit for a single item: '..F.Money(deposit)..' ('..(depositSource or 'Unknown')..'). Failed listings: '..F.db.failures..'; modeled loss per item: '..F.Money(deposit and deposit*F.db.failures)..'. A successful sale refunds its deposit; stack deposits may differ.',
    'Locations and levels: QuestieDB. Drop percentages: Questie reference data, NOT measured Forever rates. Rates, spawn positions and availability may differ on this server. Gathering skill, quest gating and access requirements are not verified.',
    'Selected source: '..best.name..'. Other outdoor sources are listed below; check their levels before travelling.'}
  local shown=0
  for _,source in ipairs(r.sources) do
    shown=shown+1; if shown>60 then break end
    local heading
    if source.kind=='npc' then
      heading=source.name..' (NPC '..source.id..') - levels '..(source.minLevel or source.level)..'-'..source.level..'; suggested min '..source.level
      if source.level>F.FarmLevel() then heading=heading..' [ABOVE YOUR FILTER LEVEL]' end
    else heading=source.name..' (object '..source.id..') - minimum level and required gathering skill unknown' end
    local rate=source.rate and string.format('%.2f%% (%s reference)',source.rate,source.rateSource) or 'Unknown - no supported percentage'
    local locations={}
    for _,place in ipairs(source.places) do locations[#locations+1]=place.zone..': '..place.coords end
    lines[#lines+1]=heading..'\nDrop rate: '..rate..'\nWhere: '..table.concat(locations,'; ')
  end
  if #r.sources>60 then lines[#lines+1]=(#r.sources-60)..' additional sources omitted; showing the first 60 by reference rate and level.' end
  report('MobAuction - Farm: '..r.name,lines)
end
function F.RefreshFarms()
  if not F.farmPanel then return end
  local results,err,stats=F.FarmResults(); F.farmResults=results
  F.farmPage=math.max(1,math.min(F.farmPage or 1,math.max(1,math.ceil(#results/10))))
  for i,row in ipairs(F.farmRows) do
    local r=results[(F.farmPage-1)*10+i]; row.result=r
    if r then
      row:Show()
      local level=r.level and tostring(r.level) or '?'
      if r.level and r.level>F.FarmLevel() then level='|cffff8855'..level..'|r' end
      row.fields[1]:SetText(r.name); row.fields[2]:SetText(level)
      row.fields[3]:SetText(F.Money(r.net))
      row.fields[4]:SetText(r.best.rate and string.format('%.2f%%',r.best.rate) or '?')
      row.fields[5]:SetText(F.Money(r.score))
      row.fields[6]:SetText(r.best.places[1].zone)
    else row:Hide() end
  end
  F.farmLevelButton:SetText(F.farmAllLevels and 'All levels + unknown' or 'Within my level')
  F.farmStatus:SetText(string.format('%d items | page %d/%d | level %d | %d need prices | %d above level/unknown',#results,F.farmPage,math.max(1,math.ceil(#results/10)),F.FarmLevel(),stats.unpriced,stats.above))
  F.farmEmpty:SetShown(#results==0)
  F.farmEmpty:SetText(err or ('No priced farms at this level yet. Click Scan farm prices at the AH, let it finish, then Refresh.\nTry All levels for higher-level farms and objects with unknown requirements. '..stats.loading..' item names loading.'))
end
function F.ShowTab(tab)
  if not F.window then return end
  F.activeTab=tab
  if tab~='farms' then
    if F.farmPanel then F.farmPanel:Hide() end
    F.craftPanel:Show(); F.window.TitleText:SetText('|TInterface\\AddOns\\MobAuction\\Media\\Icon:18:18|t MobAuction - Crafting opportunities')
    F.Refresh(); return
  end
  F.craftPanel:Hide()
  if not F.farmPanel then
    local w=CreateFrame('Frame',nil,F.window); w:SetSize(950,560); w:SetPoint('TOPLEFT',0,-68); F.farmPanel=w
    button(w,'Scan farm prices',18,-5,150,F.ScanFarms)
    button(w,'Refresh',175,-5,80,F.RefreshFarms)
    label(w,'Character level',270,-12,100)
    local level=edit(w,375,-5,50); level:SetText(tostring(F.FarmLevel()))
    button(w,'Apply',435,-5,65,function()
      local n=tonumber(level:GetText())
      if n and n>=1 and n<=1000 and n==math.floor(n) then F.farmLevel=n; F.farmPage=1; level:ClearFocus(); F.RefreshFarms()
      else F.Say('Enter a character level from 1 to 1000.') end
    end)
    button(w,'Detect',505,-5,70,function() F.farmLevel=nil; level:SetText(tostring(F.FarmLevel())); F.farmPage=1; F.RefreshFarms() end)
    F.farmLevelButton=button(w,'',590,-5,185,function() F.farmAllLevels=not F.farmAllLevels; F.farmPage=1; F.RefreshFarms() end)
    label(w,'Click an item for creatures, locations, coordinates and drop-rate sources. Min level is a solo-farming suggestion.',18,-47,910)
    label(w,'Ranked by reference value per 100 kills; unknown rates follow by item value. All values are forecasts before deposits.',18,-67,910)
    local positions,widths={10,255,325,465,570,720},{235,60,130,95,135,185}
    local headings={'Item','Min lvl*','After cut / item','Drop %*','Per 100 kills*','Where'}
    for i,title in ipairs(headings) do label(w,title,positions[i]+10,-101,widths[i]) end
    F.farmRows={}
    for i=1,10 do
      local row=CreateFrame('Button',nil,w); row:SetSize(925,29); row:SetPoint('TOPLEFT',10,-125-(i-1)*29)
      row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight'); row.fields={}
      for j=1,6 do row.fields[j]=label(row,'',positions[j],-5,widths[j]) end
      row:SetScript('OnClick',function() if row.result then F.ShowFarmDetails(row.result) end end)
      row:SetScript('OnEnter',function(self)
        local r=self.result; if not r then return end
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:AddLine(r.name,1,.8,.3)
        GameTooltip:AddLine(r.best.name..' - '..r.best.places[1].zone,1,1,1,true)
        GameTooltip:AddLine('Suggested minimum: '..(r.level or 'Unknown')..'. Reference drop rate, not verified for Forever.',.8,.8,.8,true)
        GameTooltip:AddLine('Click for locations, costs and all source details.',.8,.8,.8,true); GameTooltip:Show()
      end)
      row:SetScript('OnLeave',function() GameTooltip:Hide() end); F.farmRows[i]=row
    end
    F.farmEmpty=label(w,'',30,-235,885)
    button(w,'< Previous',18,-430,100,function() F.farmPage=(F.farmPage or 1)-1; F.RefreshFarms() end)
    button(w,'Next >',125,-430,100,function() F.farmPage=(F.farmPage or 1)+1; F.RefreshFarms() end)
    F.farmStatus=label(w,'',240,-436,685)
    label(w,'* Min level = highest creature level at the selected source. Objects have unknown level/skill; see All levels.',18,-470,910)
    label(w,'* Rates are historical references. Model: one item per successful drop, after AH cut, before other costs.',18,-492,910)
    label(w,'Questie + QuestieDB provide locations/rates. No gold/hour or demand estimate; travel, competition and kill speed vary.',18,-514,910)
  end
  F.window.TitleText:SetText('|TInterface\\AddOns\\MobAuction\\Media\\Icon:18:18|t MobAuction - Recommended Farms')
  F.farmPanel:Show(); F.RefreshFarms()
end
SLASH_MOBAUCTION1='/moba'; SLASH_MOBAUCTION2='/mobauction'
SlashCmdList.MOBAUCTION=function(message)
  if not F.db then F.Init() end
  local cmd,rest=message:match('^(%S*)%s*(.-)%s*$'); cmd=cmd:lower()
  if cmd=='' then F.Open(); return end
  if cmd=='setup' then F.ShowSetup(); return end
  if cmd=='help' then F.ShowHelp(); return end
  if cmd=='settings' then F.ShowSettings(); return end
  if cmd=='scan' then F.Scan(); return end
  if cmd=='refresh' then F.RefreshRecipes(); F.Open(); return end
  if cmd=='deals' then F.ShowDeals(); return end
  if cmd=='catalogue' then F.ShowCatalogue(); return end
  if cmd=='learn' then F.worthLearning=true; F.Open(); if F.window then F.ShowTab('crafting') end; return end
  if cmd=='farms' then F.Open(); if F.window then F.ShowTab('farms') end; return end
  if cmd=='recipe' and F.db.recipes[tonumber(rest)] then F.ShowDetails(F.db.recipes[tonumber(rest)]); return end
  if cmd=='skill' then
    local prof,value=rest:match('^(.-)%s+(%S+)$'); local id=tonumber(prof)
    if not id then for key,name in pairs(F.professions) do if name:lower()==(prof or ''):lower() then id=key end end end
    if id and F.SetSkill(id,value) then F.Refresh(); return end
  elseif cmd=='requirement' then
    local id,value=rest:match('^(-?%d+)%s+(%S+)$'); id=tonumber(id); local n=tonumber(value)
    if id and (value=='clear' or (n and n>=0 and n<=1000 and n==math.floor(n))) then
      F.db.requirements[id]=value~='clear' and {rank=n,build=F.Build()} or nil; F.Refresh(); return
    end
  elseif cmd=='deposit' then
    local id,value=rest:match('^(%d+)%s+(%d+)$'); id=tonumber(id); value=tonumber(value)
    if id and value then F.db.deposits[id]=F.db.deposits[id] or {}; F.db.deposits[id][F.db.duration]=value; F.Refresh(); return end
  elseif cmd=='cleardeposit' and tonumber(rest) then F.db.deposits[tonumber(rest)]=nil; F.Refresh(); return
  elseif cmd=='alerts' and (rest=='on' or rest=='off') then F.db.dealAlerts=rest=='on'; F.Say('Recipe alerts '..rest); return
  else
    local key=cmd=='age' and 'maxAge' or cmd
    local limits={crafts={1,1000},cut={0,100},duration={1,3},failures={0,100},maxAge={0,30},dealPercent={1,99},dealSaving={0,100000000}}
    if cmd=='discount' then key='dealPercent' elseif cmd=='saving' then key='dealSaving' end
    local range,value=limits[key],tonumber(rest)
    if range and value and value>=range[1] and value<=range[2] and value==math.floor(value) then F.db[key]=value; F.Refresh(); return end
  end
  F.Say('/moba setup | scan | refresh | catalogue | deals | learn | farms | recipe RECIPEID')
  F.Say('/moba skill PROFESSION LEVEL (or auto) | requirement RECIPEID LEVEL (or clear)')
  F.Say('/moba crafts 5 | cut 5 | duration 1 | failures 1 | age 1 | deposit ITEMID COPPER | cleardeposit ITEMID')
  F.Say('/moba alerts on/off | discount 40 (percent) | saving 1000 (copper)')
end
