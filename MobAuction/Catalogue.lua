local _, F = ...
-- A reference catalogue describes transformations. Character imports remain the
-- authority for learned status; static discovery IDs are never crafting data.
local BATCH, DELAY = 12, 0.02
local state
local function positive(n) return type(n)=='number' and n>0 and n<math.huge end
local function identifier(n) return positive(n) and n==math.floor(n) end
local registryProfessions={alchemy=171,blacksmithing=164,cooking=185,enchanting=333,engineering=202,
  first_aid=129,fishing=356,herbalism=182,leatherworking=165,mining=186,skinning=393,tailoring=197}
local function registry(s)
  local data=RecipeRegistryRecipeMetadata
  local version=type(data)=='table' and data.metadataVersion
  if s.registryChecked and s.registry==data and s.registryVersion==version then return end
  s.registryChecked=true; s.registry=data; s.registryVersion=version; s.registryRecipes={}; s.registryIDs={}; s.registryItems={}
  s.registryCount=0; s.registryBuild=nil; s.registryRejected=nil
  if data==nil then return end
  if type(data)~='table' or data.flavor~='forever' or data.schemaVersion~=1 or type(version)~='string'
      or type(data.recipesBySpellId)~='table' then
    s.registryRejected='Recipe Registry needs supported Forever metadata'; return
  end
  local family,sourceBuild=version:match('^forever%-ingame%-(%d+%.%d+%.%d+)%.(%d+)$')
  if not family then family,sourceBuild=version:match('^forever%-(%d+%.%d+%.%d+)%.(%d+)$') end
  local clientVersion=F.Safe(GetBuildInfo)
  if not sourceBuild or family~=clientVersion or not tonumber(s.build) then
    s.registryRejected='Recipe Registry metadata does not match this Forever client family'; return
  end
  s.registryRejected=nil
  s.registryBuild=sourceBuild
  -- This is an optional data adapter, not a dependency on Registry's UI or guild
  -- tracking. Its Forever data is a research forecast until this client verifies
  -- each recipe; even an exact build match does not prove current availability.
  for id,entry in pairs(data.recipesBySpellId) do
    if identifier(id) and type(entry)=='table' then
      s.registryIDs[#s.registryIDs+1]=id; s.registryCount=s.registryCount+1
      local profession=registryProfessions[entry.profession]
      local made=entry.createdCount==nil and 1 or entry.createdCount
      local okay=profession and identifier(entry.createdItemId) and identifier(made)
        and entry.removed~=true and entry.bopOutput~=true and entry.selfOnlyOutputless~=true
        and type(entry.reagents)=='table' and #entry.reagents>0
      local reagents={}
      if okay then
        for _,reagent in ipairs(entry.reagents) do
          if type(reagent)~='table' or not identifier(reagent.itemId) or not identifier(reagent.count) then
            okay=false; break
          end
          reagents[#reagents+1]={itemID=reagent.itemId,qty=reagent.count}
        end
      end
      if okay then
        s.registryRecipes[id]={id=id,profession=profession,output=entry.createdItemId,made=made,reagents=reagents,
          name=type(entry.name)=='string' and entry.name or nil,reader='registry',referenceOnly=true,databaseReference=true,
          professionVerified=false,databaseSource='Recipe Registry Forever',sourceBuild=sourceBuild,sourceDataBuild=sourceBuild,
          databaseBuildMismatch=sourceBuild~=s.build,
          databaseRequiredSkill=identifier(entry.requiredSkill) and entry.requiredSkill or nil,
          databaseRecipeItemID=identifier(entry.recipeItemId) and entry.recipeItemId or nil}
        if identifier(entry.recipeItemId) then
          local ids=s.registryItems[entry.recipeItemId] or {}; s.registryItems[entry.recipeItemId]=ids
          ids[#ids+1]=id
        end
      end
    end
  end
  table.sort(s.registryIDs)
end
local function ownSource(api)
  return api and not (F.Safe(api.IsTradeSkillLinked) or F.Safe(api.IsTradeSkillGuild) or F.Safe(api.IsNPCCrafting))
end
local function valid(recipe,build)
  if type(recipe)~='table' or not identifier(recipe.id) or recipe.observedBuild~=build
      or recipe.professionVerified~=true or recipe.problem or not identifier(recipe.profession)
      or not identifier(recipe.output) or not identifier(recipe.made)
      or type(recipe.reagents)~='table' or #recipe.reagents==0 then return false end
  for _,reagent in ipairs(recipe.reagents) do
    if type(reagent)~='table' or not identifier(reagent.itemID) or not identifier(reagent.qty) then return false end
  end
  return true
end
local function context()
  if not F.db then return end
  local build=F.Build()
  if not state or state.db~=F.db or state.build~=build then
    local saved=F.db.catalogue
    if type(saved)~='table' or saved.build~=build or type(saved.recipes)~='table' then
      saved={build=build,recipes={}}; F.db.catalogue=saved
    end
    state={db=F.db,build=build,saved=saved,queue={},head=1,queued={},attempted={},knowledge={},
      seen={},rejected={},total=0,processed=0,unavailable=0,running=false,complete=false}
    for id,recipe in pairs(saved.recipes) do
      if type(recipe)~='table' or id~=recipe.id or not valid(recipe,build) or recipe.referenceOnly~=true then saved.recipes[id]=nil
      else
        -- Never persist a character's knowledge inferred by a previous session.
        recipe.learned=nil; recipe.observedSkill=nil
      end
    end
  end
  registry(state)
  return state
end
local function clone(recipe)
  local r={}
  for k,v in pairs(recipe) do r[k]=v end
  r.reagents={}
  for i,v in ipairs(recipe.reagents) do r.reagents[i]={itemID=v.itemID,qty=v.qty} end
  r.referenceOnly=true
  return r
end
function F.CatalogueRecipes(onlyProfessions)
  local s=context(); local recipes={}
  if not s then return recipes end
  local function included(recipe)
    return type(onlyProfessions)~='table' or onlyProfessions[recipe.profession]==true
  end
  for id,recipe in pairs(s.registryRecipes or {}) do
    if not s.rejected[id] and included(recipe) then
      local r=clone(recipe)
      local name=r.name or (C_Spell and F.Safe(C_Spell.GetSpellName,id))
      if type(name)=='string' and name~='' then recipe.name=name; r.name=name else r.name='Recipe '..id end
      recipes[id]=r
    end
  end
  for id,recipe in pairs(s.saved.recipes) do
    if valid(recipe,s.build) and included(recipe) then
      local r=clone(recipe)
      local knowledge=s.knowledge[id]
      if knowledge then r.learned=knowledge.learned; r.observedSkill=knowledge.skill; r.knowledgeVerified=true end
      recipes[id]=r
    end
  end
  -- Imports include new Forever IDs even when no discovery seed existed. Copy
  -- their verified facts; never replace or relabel the character's saved import.
  for id,recipe in pairs(F.db.recipes or {}) do
    if type(recipe)=='table' and id==recipe.id and valid(recipe,s.build) and recipe.reader=='modern' and included(recipe) then
      local current=recipes[id]
      local newer=current and current.reader=='catalogue' and s.knowledge[id]
        and (type(recipe.observedAt)~='number' or current.observedAt>recipe.observedAt)
      if newer then
        -- A same-build import may predate a freshly learned spell or a hotfix.
        -- Preserve matching trainer evidence without replacing new live facts.
        if current.profession==recipe.profession and current.output==recipe.output then
          for _,key in ipairs({'trainerAvailable','trainerSeen','trainerName','trainingCost'}) do current[key]=recipe[key] end
          if current.learned and recipe.learned and positive(recipe.observedSkill) then
            current.observedSkill=math.min(current.observedSkill or recipe.observedSkill,recipe.observedSkill)
          end
        end
      else recipes[id]=clone(recipe) end
    end
  end
  return recipes
end
local function enqueue(s,id)
  if not identifier(id) then return false end
  if not s.seen[id] then s.seen[id]=true; s.total=s.total+1 end
  if s.queued[id] or s.attempted[id] then return false end
  s.queue[#s.queue+1]=id; s.queued[id]=true
  return true
end
local function readRecipe(s,id)
  local api=C_TradeSkillUI
  if not ownSource(api) then return nil,'source' end
  local info=F.Safe(api.GetRecipeInfo,id)
  if info~=nil and (type(info)~='table' or info.recipeID~=id) then return nil,'identity' end
  if type(info)=='table' and (info.disabled or info.isRecraft or info.isSalvageRecipe or info.isDummyRecipe
      or info.isGatheringRecipe) then return nil,'unsupported' end
  local owner=F.Safe(api.GetProfessionInfoByRecipeID,id)
  local profession=F.ProfessionIDFromInfo(owner)
  if not identifier(profession) then return nil,'owner' end
  local schematic=F.Safe(api.GetRecipeSchematic,id,false)
  if type(schematic)~='table' or schematic.recipeID~=id then return nil,'schematic' end
  if schematic.isRecraft or not identifier(schematic.outputItemID) or not identifier(schematic.quantityMin) then
    return nil,'unsupported'
  end
  local recipeTypes=Enum and Enum.TradeskillRecipeType
  if recipeTypes and schematic.recipeType and schematic.recipeType~=recipeTypes.Item then return nil,'unsupported' end
  local slots=schematic.reagentSlotSchematics
  if type(slots)~='table' or #slots==0 then return nil,'reagents' end
  local reagents={}
  for _,slot in ipairs(slots) do
    if type(slot)~='table' then return nil,'reagents' end
    local quantity=slot.quantityRequired
    if quantity~=nil and (type(quantity)~='number' or quantity<0 or quantity~=math.floor(quantity)) then return nil,'reagents' end
    local basic=slot.reagentType==nil or (Enum and Enum.CraftingReagentType and slot.reagentType==Enum.CraftingReagentType.Basic)
    if positive(quantity) then
      local options=slot.reagents
      if not basic or type(options)~='table' or #options~=1 or type(options[1])~='table'
          or not identifier(options[1].itemID) or positive(options[1].currencyID) then return nil,'unsupported' end
      local slotTypes=Enum and Enum.TradeskillSlotDataType
      if slotTypes and slot.dataSlotType and slot.dataSlotType~=slotTypes.Reagent then return nil,'unsupported' end
      if type(slot.variableQuantities)=='table' and #slot.variableQuantities>0 then return nil,'unsupported' end
      reagents[#reagents+1]={itemID=options[1].itemID,qty=quantity}
    elseif slot.required then return nil,'reagents' end
  end
  if #reagents==0 then return nil,'reagents' end
  -- Recheck mutable identity after reading the schematic. A source switch may
  -- invalidate character knowledge even though the spell itself is valid data.
  if not ownSource(api) or profession~=F.ProfessionIDFromInfo(F.Safe(api.GetProfessionInfoByRecipeID,id)) then
    return nil,'source'
  end
  local recipe={id=id,profession=profession,name=(info and info.name) or schematic.name or tostring(id),
    output=schematic.outputItemID,made=schematic.quantityMin,reagents=reagents,
    observedBuild=s.build,observedAt=time(),professionVerified=true,reader='catalogue',referenceOnly=true}
  local knowledge
  if info and type(info.learned)=='boolean' then
    local skill=F.currentProfessionsComplete and F.currentProfessions and F.currentProfessions[profession]
    knowledge={learned=info.learned,skill=positive(skill) and skill or nil}
  end
  return recipe,knowledge
end
local function updated()
  if F.window and F.window:IsShown() and F.Refresh then F.Refresh() end
  if F.details and F.details:IsShown() and F.RefreshDetails then F.RefreshDetails() end
end
function F.ProcessCatalogueBatch()
  local s=context()
  if not s or not s.running then return false end
  if not ownSource(C_TradeSkillUI) then
    s.running=false; s.paused=true; updated(); return false
  end
  for _=1,BATCH do
    local id=s.queue[s.head]
    if not id then
      s.running=false; s.queue={}; s.head=1; s.paused=false; updated(); return false
    end
    s.head=s.head+1; s.queued[id]=nil
    local recipe,knowledge=readRecipe(s,id)
    if recipe then
      s.saved.recipes[id]=recipe; s.knowledge[id]=knowledge; s.attempted[id]='validated'; s.rejected[id]=nil
    else
      -- An unavailable API does not erase a same-build reference. Contradictory
      -- identities or unsupported transformations must invalidate old evidence.
      if knowledge=='identity' or knowledge=='unsupported' then s.saved.recipes[id]=nil; s.rejected[id]=true end
      s.knowledge[id]=nil; s.attempted[id]='unavailable'; s.unavailable=s.unavailable+1
    end
    s.processed=s.processed+1
  end
  return true
end
local function schedule(s)
  if s.scheduled or not s.running or not C_Timer or not C_Timer.After then return end
  s.scheduled=true
  C_Timer.After(DELAY,function()
    s.scheduled=false
    if state~=s or s.db~=F.db or s.build~=F.Build() or not s.running then return end
    if F.ProcessCatalogueBatch() then schedule(s) end
  end)
end
function F.RefreshCatalogue(reason)
  local s=context(); if not s then return false end
  local now=time()
  local retry=false
  if reason=='profession' and (not s.lastRetry or now-s.lastRetry>=5) then
    -- A newly opened profession can make previously unavailable schematics
    -- readable. Coalesce frequent trade-skill events into one bounded pass.
    s.lastRetry=now; retry=true
    for id,result in pairs(s.attempted) do if result=='unavailable' then s.attempted[id]=nil end end
    s.unavailable=0
  end
  local api=C_TradeSkillUI
  if ownSource(api) then
    local ids=F.Safe(api.GetAllRecipeIDs)
    local current,signature={},{}
    for _,id in ipairs(type(ids)=='table' and ids or {}) do
      if identifier(id) then current[#current+1]=id; signature[#signature+1]=tostring(id) end
    end
    local key=table.concat(signature,',')
    local changed=key~=s.professionList
    s.professionList=key
    for _,id in ipairs(current) do
      if (changed or retry) and not s.queued[id] then s.attempted[id]=nil end
      enqueue(s,id)
    end
  end
  for id,recipe in pairs(F.db.recipes or {}) do enqueue(s,id); if type(recipe)=='table' then enqueue(s,recipe.id) end end
  for id in pairs(s.saved.recipes) do enqueue(s,id) end
  for _,id in ipairs(s.registryIDs or {}) do enqueue(s,id) end
  for _,id in ipairs(F.catalogueCandidates or {}) do enqueue(s,id) end
  if s.head>#s.queue then return false end
  s.running=true; s.paused=false; schedule(s)
  return true
end
function F.QueueCatalogueRecipeID(id)
  local s=context(); if not s then return false end
  local added=enqueue(s,id)
  if added then s.running=true; s.paused=false; schedule(s) end
  return added
end
function F.CancelCatalogueRefresh()
  if state then state.running=false; state.paused=true end
end
function F.CatalogueStatus()
  local s=context()
  local result={total=0,processed=0,validated=0,unavailable=0,running=false,complete=false}
  if not s then return result end
  result.references=0
  for _,recipe in pairs(F.CatalogueRecipes()) do
    if valid(recipe,s.build) then result.validated=result.validated+1
    elseif recipe.databaseReference then result.references=result.references+1 end
  end
  result.total=s.total; result.processed=s.processed; result.unavailable=s.unavailable
  result.running=s.running; result.paused=s.paused; result.pending=math.max(0,#s.queue-s.head+1)
  result.provider=s.registryBuild and 'Recipe Registry Forever' or nil
  result.providerBuild=s.registryBuild; result.providerRecipes=s.registryCount; result.providerRejected=s.registryRejected
  return result
end
function F.CatalogueStatusText()
  local s=F.CatalogueStatus()
  local progress=s.running and ('; '..s.pending..' checks pending') or (s.paused and '; checks paused' or '')
  local database=(s.references or 0)>0 and ('; '..s.references..' database forecasts (build '..s.providerBuild..', unverified)') or ''
  local rejected=s.providerRejected and ('; '..s.providerRejected) or ''
  return s.validated..' verified reference entries'..database..progress..rejected..'. All Forever entries are not yet verified.'
end
function F.CatalogueRecipeHintsForItem(itemID)
  local s=context(); local result={}
  if not s or not identifier(itemID) then return result end
  for _,id in ipairs(s.registryItems[itemID] or {}) do
    if not s.rejected[id] then result[#result+1]=id end
  end
  return result
end
function F.CatalogueRecipeIDsForItem(itemID)
  local ids,seen={},{}
  if not identifier(itemID) then return ids end
  local function add(id)
    if identifier(id) and not seen[id] then ids[#ids+1]=id; seen[id]=true; F.QueueCatalogueRecipeID(id) end
  end
  -- Only current-client item effects/typed learning lines establish the taught
  -- spell. Historical recipe-item associations cannot prove this relationship.
  local fn=C_Item and C_Item.GetItemSpell or GetItemSpell
  if type(fn)=='function' then
    local ok,_,id=pcall(fn,itemID)
    if ok then add(id) end
  end
  local tooltip=C_TooltipInfo and F.Safe(C_TooltipInfo.GetItemByID,itemID)
  local types=Enum and Enum.TooltipDataLineType
  for _,line in ipairs(type(tooltip)=='table' and tooltip.lines or {}) do
    if types and ((types.LearnableSpell and line.type==types.LearnableSpell)
        or (types.ItemSpellTriggerLearn and line.type==types.ItemSpellTriggerLearn)) then add(line.spellID) end
  end
  -- These exact item effects still need crafting identity/owner validation by
  -- the caller. General 'Learning' wrapper spells are not promoted to recipes.
  local s=context()
  local verified={}
  if s then
    for _,id in ipairs(ids) do
      local imported=F.db.recipes and F.db.recipes[id]
      if valid(s.saved.recipes[id],s.build) or (valid(imported,s.build) and imported.reader=='modern') then
        verified[#verified+1]=id
      end
    end
  end
  return verified
end

-- Start automatically after addon initialization and revisit unavailable data
-- when a profession opens. Frequent list/detail notifications share one pass.
if type(CreateFrame)=='function' then
  local frame=CreateFrame('Frame')
  local pending,requestDB,reason,elapsed=false,nil,nil,0
  local function runRequest()
    if not pending then return end
    pending=false; elapsed=0
    if requestDB~=F.db then return end
    F.RefreshCatalogue(reason)
  end
  local function request(why)
    if not F.db then return end
    requestDB=F.db
    if why=='profession' or not reason then reason=why end
    if pending then return end
    pending=true; elapsed=0
    if C_Timer and C_Timer.After then C_Timer.After(0.25,runRequest) end
  end
  for _,event in ipairs({'PLAYER_LOGIN','ADDON_LOADED','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE',
      'TRADE_SKILL_DETAILS_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGING','TRADE_SKILL_DATA_SOURCE_CHANGED',
      'NEW_RECIPE_LEARNED','CRAFT_SHOW','CRAFT_UPDATE'}) do
    pcall(frame.RegisterEvent,frame,event)
  end
  frame:SetScript('OnEvent',function(_,event,arg)
    if event=='ADDON_LOADED' then
      if arg=='RecipeRegistry_Forever' then request('provider') end
    elseif event=='PLAYER_LOGIN' then request('login')
    elseif event=='TRADE_SKILL_DATA_SOURCE_CHANGING' then F.CancelCatalogueRefresh()
    else
      if event=='NEW_RECIPE_LEARNED' then
        local s=context()
        if s then s.professionList=nil; if identifier(arg) then s.attempted[arg]=nil; enqueue(s,arg) end end
      end
      request('profession')
    end
  end)
  frame:SetScript('OnUpdate',function(_,delta)
    if C_Timer and C_Timer.After then return end
    elapsed=elapsed+(tonumber(delta) or 0)
    if pending then
      if elapsed>=0.25 then runRequest() end
    elseif state and state.running and elapsed>=DELAY then
      elapsed=0; F.ProcessCatalogueBatch()
    end
  end)
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback('Professions.ProfessionSelected',function() request('profession') end,frame)
    EventRegistry:RegisterCallback('ProfessionsFrame.Show',function() request('profession') end,frame)
  end
end
