local _, F = ...
local function saveRecipe(r)
  local previous=F.db.recipes[r.id]
  if previous and previous.profession==r.profession and previous.observedBuild==r.observedBuild and previous.output==r.output then
    for _,key in ipairs({'trainerAvailable','trainerSeen','trainerName','trainingCost'}) do r[key]=previous[key] end
    if previous.learned and r.learned and previous.observedSkill then
      r.observedSkill=math.min(previous.observedSkill,r.observedSkill or previous.observedSkill)
    end
  end
  F.db.recipes[r.id]=r
end
local function importStatus(attempt, reason, message)
  attempt.reason=reason; attempt.why=message
  F.recipeImportStatus=message
end
local function activeProfession(api)
  -- Match Blizzard's Professions.GetProfessionInfo: the selected child line
  -- owns the displayed list; the base is only a fallback when no child exists.
  local child=F.Safe(api.GetChildProfessionInfo)
  local base=F.Safe(api.GetBaseProfessionInfo)
  if type(child)=='table' and type(child.professionID)=='number' and child.professionID>0 then
    return child,'child',base
  end
  return base,'base',base
end
local function boundedName(info)
  local name=type(info)=='table' and (info.parentProfessionName or info.professionName)
  return type(name)=='string' and name:sub(1,160) or nil
end
local function readModern(attempt)
  local api = C_TradeSkillUI
  if not api or (not api.GetBaseProfessionInfo and not api.GetChildProfessionInfo) then
    importStatus(attempt,'modern_unavailable','Open a crafting profession to import its entries. This client needs a visible profession window.')
    return 0
  end
  local profession,source,base=activeProfession(api)
  attempt.baseID=F.ProfessionIDFromInfo(base); attempt.baseName=boundedName(base)
  attempt.source=source
  local id = F.ProfessionIDFromInfo(profession)
  if not id then
    importStatus(attempt,'profession_loading','The active profession is not ready. Select Cooking or another crafting profession and wait for its crafting list.')
    return 0
  end
  attempt.professionID=id; attempt.professionName=boundedName(profession)
  attempt.skillLineID=profession.professionID; attempt.sourceCounter=profession.sourceCounter
  local sourceCounter=profession.sourceCounter
  local skillLineID=profession.professionID
  local rank=profession.skillLevel
  -- Capture a complete snapshot before discovery or any writes. Another addon
  -- or an asynchronous source change can leave the old recipe list in the API.
  local ids = F.Safe(api.GetAllRecipeIDs)
  if type(ids)~='table' then
    importStatus(attempt,'list_loading','The profession list is unavailable or still loading. Keep its crafting window open while it loads.')
    return 0
  end
  attempt.idCount=#ids
  if #ids==0 then
    importStatus(attempt,'empty_list','The open profession has not returned any crafting entries yet. Select its crafting page to import entries automatically.')
    return 0
  end
  local pending,loading={},0
  local function pendingEntry(recipeID,reason)
    loading=loading+1
    if not attempt.failedRecipeID then attempt.failedRecipeID=recipeID; attempt.loadingReason=reason end
  end
  for _, recipeID in ipairs(ids) do
    local owned=true
    if api.GetProfessionInfoByRecipeID then
      local owner=F.Safe(api.GetProfessionInfoByRecipeID,recipeID)
      local ownerID=F.ProfessionIDFromInfo(owner)
      if not ownerID then
        owned=false; pendingEntry(recipeID,'profession identity loading')
      elseif ownerID~=id then
        local expected=ownerID and F.professions[ownerID]
        attempt.ownerID=ownerID; attempt.ownerName=boundedName(owner); attempt.failedRecipeID=recipeID
        importStatus(attempt,'profession_mismatch',expected and (expected..' crafting entries do not match the active '..(F.professions[id] or 'profession')..' window. Reopen '..expected..' to import its entries automatically.')
          or 'The crafting list belongs to a different profession. Reopen its crafting window to import automatically.')
        return 0
      end
    else
      -- Clients without the recipe-specific API must provide a visible legacy
      -- window with an independent skill-line name before we trust this source.
      local line
      if TradeSkillFrame and TradeSkillFrame:IsShown() then line=F.Safe(GetTradeSkillLine) end
      if not line and CraftFrame and CraftFrame:IsShown() then line=F.Safe(GetCraftDisplaySkillLine) end
      if F.ProfessionIDByName(line)~=id then
        importStatus(attempt,'identity_unavailable','The profession identity could not be checked. Reopen its crafting window to import automatically.')
        return 0
      end
    end
    if owned then
      local info = F.Safe(api.GetRecipeInfo, recipeID)
      local schematic = type(info)=='table' and F.Safe(api.GetRecipeSchematic, recipeID, false)
      if type(info)~='table' then pendingEntry(recipeID,'recipe information loading')
      elseif type(info.learned)~='boolean' then pendingEntry(recipeID,'learned status loading')
      elseif type(schematic)~='table' then pendingEntry(recipeID,'ingredients loading')
      else
        local r = { id = recipeID, profession = id, name = info.name or schematic.name or tostring(recipeID),
          output = schematic.outputItemID, made = schematic.quantityMin or 1, reagents = {},
          learned = info.learned == true, observedBuild = F.Build(), observedAt = time(),
          observedSkill = type(rank)=='number' and rank>0 and rank or F.db.detectedSkills[id],
          professionVerified = true, reader = 'modern' }
        if type(r.output)~='number' or r.output<=0 then r.output=nil end
        if type(r.made)~='number' or r.made<=0 then r.made=1; r.problem='Recipe yield unavailable' end
        if not r.output then r.problem = 'No auctionable item output' end
        if info.disabled or info.isRecraft or info.isSalvageRecipe then r.problem = info.disabledReason or 'Unsupported recipe operation' end
        -- Minimum yield keeps variable-output recipes conservative.
        local slots=schematic.reagentSlotSchematics
        local ingredientsLoading=r.output and (type(slots)~='table' or #slots==0)
        for _, slot in ipairs(type(slots)=='table' and slots or {}) do
          local basic = slot.reagentType == nil or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
          if basic and (slot.quantityRequired or 0) > 0 then
            local options = slot.reagents or {}
            if #options == 1 and options[1].itemID then
              r.reagents[#r.reagents + 1] = { itemID = options[1].itemID, qty = slot.quantityRequired }
            else r.problem = 'Unsupported reagent choices or currency' end
          elseif (slot.quantityRequired or 0) > 0 or slot.required then
            r.problem = 'Unsupported required reagent slot'
          end
        end
        if #r.reagents == 0 then r.problem = r.problem or 'Recipe reagent data unavailable' end
        local _, _, _, _, _, _, _, _, _, _, _, _, _, bind = F.ItemInfo(r.output or 0)
        if bind == 1 or bind == 4 then r.problem = 'Output cannot be auctioned' end
        if r.output then F.ItemName(r.output) end
        if ingredientsLoading then pendingEntry(recipeID,'ingredient quantities loading')
        else pending[#pending+1]=r end
      end
    end
  end
  local after,afterSource=activeProfession(api)
  if F.ProfessionIDFromInfo(after)~=id or after.professionID~=skillLineID or afterSource~=source or after.sourceCounter~=sourceCounter
      or F.Safe(api.IsDataSourceChanging)==true or F.Safe(api.IsTradeSkillReady)==false
      or F.Safe(api.IsTradeSkillLinked) or F.Safe(api.IsTradeSkillGuild) or F.Safe(api.IsNPCCrafting) then
    importStatus(attempt,'source_changed','Profession changed while crafting entries were loading. Keep the new crafting list open while it loads.')
    return 0
  end
  attempt.loadingCount=loading
  if #pending==0 then
    importStatus(attempt,'entries_loading','Crafting entries are still loading ('..(attempt.loadingReason or 'details unavailable')..'). Existing saved entries were kept.')
    return 0
  end
  local name=profession.parentProfessionName or profession.professionName
  if type(name)~='string' or name=='' then name=F.professions[id] or ('Profession '..id) end
  F.professions[id]=name; F.db.professionNames[id]=name
  for _,r in ipairs(pending) do saveRecipe(r) end
  attempt.reader='modern'; attempt.count=#pending
  local imported='Imported '..#pending..' '..name..' '..F.RecipeTerm(id,#pending~=1)..'.'
  if loading>0 then
    importStatus(attempt,'partial',imported..' '..loading..' more still loading; saved entries were kept.')
  else attempt.reason='imported'; attempt.why=imported end
  -- Do not let skill discovery change the context before recipes are captured.
  F.DetectSkill(id,profession)
  return #pending
end
local function linkID(link,kind)
  return type(link)=='string' and tonumber(link:match(kind..':(%d+)')) or nil
end
local function readLegacy(craft,attempt)
  local reader,frame
  if craft then
    frame=CraftFrame
    reader={line=GetCraftDisplaySkillLine,count=GetNumCrafts,itemLink=GetCraftItemLink,recipeLink=GetCraftRecipeLink,
      numReagents=GetCraftNumReagents,reagentInfo=GetCraftReagentInfo,reagentLink=GetCraftReagentItemLink}
  else
    frame=TradeSkillFrame
    reader={line=GetTradeSkillLine,count=GetNumTradeSkills,itemLink=GetTradeSkillItemLink,recipeLink=GetTradeSkillRecipeLink,
      numReagents=GetTradeSkillNumReagents,reagentInfo=GetTradeSkillReagentInfo,reagentLink=GetTradeSkillReagentItemLink}
  end
  if not frame or not frame:IsShown() then return 0 end
  if F.Safe(IsTradeSkillLinked) or F.Safe(IsTradeSkillGuild) then return 0 end
  local name,rank
  local line=reader.line
  if type(line)=='function' then
    local ok; ok,name,rank=pcall(line)
    if not ok then return 0 end
  end
  local profession=F.ProfessionIDByName(name)
  if not profession then return 0 end
  local total=F.Safe(reader.count) or 0
  local count,loading=0,0
  for i=1,total do
    local recipeName,kind
    if craft then
      if GetCraftInfo then local ok,sub; ok,recipeName,sub,kind=pcall(GetCraftInfo,i); if not ok then recipeName=nil end end
    elseif GetTradeSkillInfo then
      local ok; ok,recipeName,kind=pcall(GetTradeSkillInfo,i); if not ok then recipeName=nil end
    end
    if recipeName and kind and kind~='header' and kind~='subheader' then
      local outputLink=F.Safe(reader.itemLink,i)
      local recipeLink=F.Safe(reader.recipeLink,i)
      local spellID=linkID(recipeLink,'enchant') or linkID(recipeLink,'spell') or linkID(outputLink,'enchant')
      local output=linkID(outputLink,'item')
      -- Some legacy windows expose only an item link. Allocate a persistent
      -- local ID instead of treating the output item ID as a recipe spell ID.
      local signature=profession..':'..tostring(output or '')..':'..recipeName
      F.db.legacyRecipeKeys=F.db.legacyRecipeKeys or {}
      local oldID=F.db.legacyRecipeKeys[signature]
      local id=spellID or oldID
      if not id then
        id=math.min(F.db.nextLegacyRecipeID or -1,-1)
        while F.db.recipes[id] do id=id-1 end
        F.db.nextLegacyRecipeID=id-1
      end
      if oldID and spellID and oldID~=spellID then F.db.recipes[oldID]=nil end
      F.db.legacyRecipeKeys[signature]=id
      local made=craft and 1 or F.Safe(GetTradeSkillNumMade,i)
      local r={id=id,profession=profession,name=recipeName,output=output,made=made or 1,reagents={},
        learned=true,observedBuild=F.Build(),observedAt=time(),
        observedSkill=type(rank)=='number' and rank>0 and rank or F.db.detectedSkills[profession],reader='legacy'}
      local incomplete=output and (type(made)~='number' or made<=0)
      if not output then r.problem='No auctionable item output' end
      if type(made)~='number' or made<=0 then r.problem=r.problem or 'Recipe yield unavailable' end
      local reagentCount=F.Safe(reader.numReagents,i)
      if type(reagentCount)~='number' or reagentCount<1 then
        r.problem=r.problem or 'Recipe reagent data unavailable'; incomplete=output~=nil
      else
        for j=1,reagentCount do
          local fn=reader.reagentInfo
          local ok,reagentName,texture,qty
          if type(fn)=='function' then ok,reagentName,texture,qty=pcall(fn,i,j) end
          local item=linkID(F.Safe(reader.reagentLink,i,j),'item')
          if ok and item and type(qty)=='number' and qty>0 then r.reagents[#r.reagents+1]={itemID=item,qty=qty}
          else r.problem=r.problem or 'Recipe reagent data loading'; incomplete=output~=nil end
        end
      end
      local _,_,_,_,_,_,_,_,_,_,_,_,_,bind=F.ItemInfo(output)
      if bind==1 or bind==4 then r.problem='Output cannot be auctioned' end
      if output then F.ItemName(output) end
      if incomplete then loading=loading+1 end
      saveRecipe(r); count=count+1
    end
  end
  F.DetectSkill(profession,{skillLevel=rank})
  if count>0 then
    attempt.reader='legacy'; attempt.professionID=profession; attempt.professionName=name
    attempt.idCount=total
    attempt.legacyLoadingCount=(attempt.legacyLoadingCount or 0)+loading
  end
  return count
end
local function recipeSourceIsOpen()
  return F.recipeSourceOpen or (TradeSkillFrame and TradeSkillFrame:IsShown())
    or (CraftFrame and CraftFrame:IsShown()) or (ProfessionsFrame and ProfessionsFrame:IsShown())
end
function F.ReadRecipes()
  if not F.db then return 0 end
  -- AH scans and filter changes use saved imports. Closed profession APIs can
  -- retain a recipe list whose global profession has already changed.
  if not recipeSourceIsOpen() then return 0 end
  -- One bounded snapshot is saved with the character so a failed live import
  -- can be diagnosed after logout without guessing from older recipe records.
  local attempt={version=F.VERSION,build=F.Build(),time=time(),count=0}
  F.db.lastImportAttempt=attempt
  F.recipeImportStatus=nil
  local api=C_TradeSkillUI
  local changing=api and F.Safe(api.IsDataSourceChanging)
  local ready=api and F.Safe(api.IsTradeSkillReady)
  attempt.changing=changing; attempt.ready=ready
  -- A current API answer supersedes a missed CHANGED event. A transient false
  -- ready result does not set a latch that would block later refreshes.
  if changing==false or ready==true then F.recipeSourceChanging=false end
  if changing==true or ready==false or F.recipeSourceChanging then
    importStatus(attempt,'not_ready','The profession is still loading. Keep its crafting window open while it loads.')
    F.lastRecipeImport=0; return 0
  end
  if api and (F.Safe(api.IsTradeSkillLinked) or F.Safe(api.IsTradeSkillGuild) or F.Safe(api.IsNPCCrafting)) then
    importStatus(attempt,'external_source','Open this character\'s own crafting profession to import learned entries.')
    F.lastRecipeImport=0; return 0
  end
  local count=readModern(attempt) or 0
  if count==0 then
    count=readLegacy(false,attempt)+readLegacy(true,attempt)
    if count>0 then
      F.recipeImportStatus=nil; attempt.count=count; attempt.reason='imported'
      attempt.why='Imported '..count..' '..(attempt.professionName or 'profession')..' '..F.RecipeTerm(attempt.professionID,count~=1)..'.'
      attempt.loadingCount=attempt.legacyLoadingCount or 0; attempt.legacyLoadingCount=nil
      if attempt.loadingCount>0 then
        importStatus(attempt,'partial',attempt.why..' '..attempt.loadingCount..' entries still loading ingredients.')
      end
    end
  end
  F.lastRecipeImport=count
  return count
end
-- SHOW can arrive before the selected profession and its schematics settle.
-- Confirm once after the event, then retry incomplete data for a bounded period.
-- Item/list events share the pending callback instead of creating more timers.
local retryDelays={0.1,0.25,0.5,1,2,4}
local retryReasons={not_ready=true,profession_loading=true,list_loading=true,empty_list=true,
  entries_loading=true,partial=true,source_changed=true,profession_mismatch=true}
local automatic={generation=0,retry=0,pending=false,limited=false,running=false}
local function cancelAutomaticImport(reset)
  automatic.generation=automatic.generation+1
  if automatic.timer and automatic.timer.Cancel then automatic.timer:Cancel() end
  automatic.timer=nil; automatic.pending=false
  if reset then automatic.retry=0; automatic.limited=false end
end
local function refreshImportUI()
  if F.window and F.window:IsShown() and F.Refresh then F.Refresh() end
  if F.details and F.details:IsShown() and F.RefreshDetails then F.RefreshDetails() end
end
local importAutomatically
local function queueAutomaticImport()
  if automatic.pending or not recipeSourceIsOpen() then return end
  local delay=retryDelays[automatic.retry+1]
  if not delay then
    automatic.limited=true
    local attempt=F.db and F.db.lastImportAttempt
    if attempt and retryReasons[attempt.reason] and not attempt.retryLimitReached then
      attempt.retryLimitReached=true
      attempt.why=attempt.why..' Reopen the profession to retry automatically.'
      F.recipeImportStatus=attempt.why
      refreshImportUI()
    end
    return
  end
  if not C_Timer or (not C_Timer.NewTimer and not C_Timer.After) then return end
  automatic.retry=automatic.retry+1; automatic.pending=true
  local generation=automatic.generation
  local function retry()
    if generation~=automatic.generation then return end
    automatic.pending=false; automatic.timer=nil
    if F.db and recipeSourceIsOpen() then importAutomatically(false) end
  end
  if C_Timer.NewTimer then automatic.timer=C_Timer.NewTimer(delay,retry)
  else C_Timer.After(delay,retry) end
end
importAutomatically=function(confirm)
  if automatic.running or not F.db or not recipeSourceIsOpen() then return end
  automatic.running=true
  local previous=F.db.lastImportAttempt
  local ok,result=pcall(F.ReadRecipes)
  automatic.running=false
  if not ok then error(result) end
  local attempt=F.db.lastImportAttempt
  if attempt~=previous then refreshImportUI() end
  if attempt and ((confirm and attempt.reason=='imported') or retryReasons[attempt.reason]) then queueAutomaticImport()
  else automatic.retry=0; automatic.limited=false end
end
local function requestAutomaticImport(reset,confirm,itemEvent)
  if not F.db or not recipeSourceIsOpen() then return end
  if reset then cancelAutomaticImport(true) end
  if automatic.pending or automatic.running then return end
  -- Unrelated item cache traffic must not restart exhausted retries, or reread
  -- a fully imported profession every time an AH item finishes loading.
  local attempt=F.db.lastImportAttempt
  if itemEvent and (automatic.limited or not attempt or not retryReasons[attempt.reason]) then return end
  importAutomatically(confirm)
end
local function closeRecipeSource()
  F.recipeSourceOpen=false; F.recipeSourceChanging=false
  cancelAutomaticImport(true)
end
local events = CreateFrame('Frame')
for _, event in ipairs({ 'ADDON_LOADED', 'TRADE_SKILL_SHOW', 'TRADE_SKILL_CLOSE', 'TRADE_SKILL_LIST_UPDATE', 'TRADE_SKILL_DETAILS_UPDATE',
  'TRADE_SKILL_DATA_SOURCE_CHANGING', 'TRADE_SKILL_DATA_SOURCE_CHANGED',
  'CRAFT_SHOW', 'CRAFT_CLOSE', 'CRAFT_UPDATE', 'SKILL_LINES_CHANGED', 'GET_ITEM_INFO_RECEIVED',
  'PLAYER_LOGIN', 'MERCHANT_SHOW', 'MERCHANT_UPDATE' }) do events:RegisterEvent(event) end
events:SetScript('OnEvent', function(_, event, name)
  if event == 'ADDON_LOADED' then
    if name == 'MobAuction' then F.Init() end
    return
  end
  if not F.db then return end
  if event=='TRADE_SKILL_CLOSE' or event=='CRAFT_CLOSE' then closeRecipeSource(); return end
  if event=='TRADE_SKILL_DATA_SOURCE_CHANGING' then
    F.recipeSourceChanging=true; cancelAutomaticImport(true)
    if recipeSourceIsOpen() then queueAutomaticImport() end
    return
  end
  if event=='TRADE_SKILL_DATA_SOURCE_CHANGED' then F.recipeSourceChanging=false end
  if event=='TRADE_SKILL_SHOW' or event=='CRAFT_SHOW' then F.recipeSourceOpen=true; F.recipeSourceChanging=false end
  if event == 'PLAYER_LOGIN' then F.DiscoverProfessions(); if not F.db.setupComplete and F.ShowSetup then F.ShowSetup() end
  elseif event == 'MERCHANT_SHOW' or event == 'MERCHANT_UPDATE' then F.ReadMerchant()
  elseif event == 'SKILL_LINES_CHANGED' then F.DiscoverProfessions()
  elseif event == 'GET_ITEM_INFO_RECEIVED' then
    requestAutomaticImport(false,false,true)
  else
    local newSource=event=='TRADE_SKILL_SHOW' or event=='CRAFT_SHOW' or event=='TRADE_SKILL_DATA_SOURCE_CHANGED'
    requestAutomaticImport(newSource,newSource)
  end
end)
-- Forever keeps the profession overview inside ProfessionsFrame and can change
-- its selected child after the ordinary game event. These existing UI callbacks
-- cover that ordering without replacing or hooking Blizzard's frame methods.
if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback('Professions.ProfessionSelected',function()
    requestAutomaticImport(true,true)
  end,events)
  EventRegistry:RegisterCallback('ProfessionsFrame.Show',function()
    requestAutomaticImport(true,true)
  end,events)
  EventRegistry:RegisterCallback('ProfessionsFrame.Hide',closeRecipeSource,events)
end
