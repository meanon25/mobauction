local _, F = ...
local subclasses={[1]=165,[2]=197,[3]=202,[4]=164,[5]=185,[6]=171,[7]=129,[8]=333,[9]=356,[10]=755,[11]=773}
local query,hookedAPI,sending,summary
local queueNextPage
F.auctionRecipes={}
F.fullScanRecipes={}
local recipeSnapshot
local supersededSnapshotOffers={}
local function positive(n) return type(n)=='number' and n>0 and n<math.huge end
local function identifier(n) return positive(n) and n==math.floor(n) end
local function fresh(seen,age) return type(seen)=='number' and time()>=seen and time()-seen<=age end
local function ownSource(api)
  return not (api and (F.Safe(api.IsTradeSkillLinked) or F.Safe(api.IsTradeSkillGuild) or F.Safe(api.IsNPCCrafting)))
end
local function newerKnowledge(reference,previous)
  return reference and reference.observedBuild==F.Build() and reference.knowledgeVerified==true
    and type(reference.learned)=='boolean'
    and (not previous or type(previous.observedAt)~='number'
      or (type(reference.observedAt)=='number' and reference.observedAt>previous.observedAt))
end
function F.ClearAuctionLearning()
  F.auctionRecipes={}; query=nil; summary=nil
end
-- A full scan is a market snapshot, not a visit-scoped browse page. Keep its
-- recipe offers separate so checking ingredients cannot erase them.
function F.ObserveFullScanRecipes(snapshot)
  if type(snapshot)~='table' or snapshot.complete~=true or type(snapshot.items)~='table' then return false end
  local offers={}
  for id,item in pairs(snapshot.items) do
    if identifier(id) and positive(item.minBuyout) then
      local name,class,subclass=item.name,item.class,item.subclass
      if class==nil then
        local n,_,_,_,_,_,_,_,_,_,_,c,s=F.ItemInfo(id)
        name=name or n; class=c; subclass=s
      end
      if class==9 or class==nil then
        offers[id]={id=id,name=name,subclass=subclass,price=item.minBuyout,seen=snapshot.seen,
          snapshot=true,ownerUnknown=item.ownerUnknown,source='Full AH scan; cheapest whole listing, availability unverified'}
        if not name then F.ItemName(id) end
      end
    end
  end
  recipeSnapshot=snapshot; F.fullScanRecipes=offers; supersededSnapshotOffers={}; summary=nil
  return true
end
local function snapshotOffers()
  local snapshot=F.GetFullScanSnapshot and F.GetFullScanSnapshot()
  if not snapshot then F.fullScanRecipes={}; recipeSnapshot=nil; return F.fullScanRecipes end
  if snapshot~=recipeSnapshot then F.ObserveFullScanRecipes(snapshot) end
  return F.fullScanRecipes
end
local function allOffers(open)
  local offers={}
  for id,listing in pairs(snapshotOffers()) do if not supersededSnapshotOffers[id] then offers[id]=listing end end
  if open then
    for id,listing in pairs(F.auctionRecipes) do
      if fresh(listing.seen,300) then offers[id]=listing else F.auctionRecipes[id]=nil end
    end
  end
  return offers
end
local function refreshUI()
  if F.window and F.window:IsShown() and F.Refresh then F.Refresh() end
  if F.details and F.details:IsShown() and F.RefreshDetails then F.RefreshDetails() end
end
local function hookBrowse(api)
  if hookedAPI==api then return true end
  if not hooksecurefunc then return false end
  local ok=pcall(hooksecurefunc,api,'SendBrowseQuery',function()
    if not sending and query then query.owned=false; query.waiting=false end
  end)
  if ok then hookedAPI=api end
  return ok
end
local function available()
  if not F.db or not F.IsAuctionHouseOpen() then F.Say('Open the auction house first.'); return end
  local api=C_AuctionHouse
  if not api or not api.SendBrowseQuery then F.Say('Recipe browsing is unavailable on this client.'); return end
  if api.IsThrottledMessageSystemReady and F.Safe(api.IsThrottledMessageSystemReady)~=true then
    F.Say('Auction house busy; try Full AH scan again shortly.'); return
  end
  return api
end
function F.ScanAuctionRecipes()
  local api=available(); if not api then return false end
  F.DiscoverProfessions()
  F.ClearAuctionLearning()
  query={owned=hookBrowse(api),waiting=true,complete=false,started=time(),ticks=0}
  sending=true
  local ok=pcall(api.SendBrowseQuery,{searchString='',sorts={},filters={},itemClassFilters={{classID=9}}})
  sending=false
  if not ok then query=nil; F.Say('The recipe browse search could not start.'); return false end
  queueNextPage()
  F.Say('Searching auction recipes. Worth Learning shows crafting profit and the recipe purchase price separately.')
  return true
end
queueNextPage=function()
  local active=query
  if not active or not active.owned or active.complete or active.paused or active.pending or not C_Timer or not C_Timer.After then return end
  active.pending=true
  C_Timer.After(0.5,function()
    active.pending=false
    if query~=active or not active.owned or active.complete or active.paused then return end
    if not F.IsAuctionHouseOpen() then return end
    active.ticks=active.ticks+1
    if time()-active.started>120 or active.ticks>240 then
      active.paused=true; summary=nil
      F.Say('Recipe browse paused waiting for the AH. Use Full AH scan to refresh the market.'); refreshUI(); return
    end
    local api=C_AuctionHouse
    if not active.waiting and api and (not api.IsThrottledMessageSystemReady or F.Safe(api.IsThrottledMessageSystemReady)==true) then
      if not F.MoreAuctionRecipes() then active.paused=true; return end
    end
    queueNextPage()
  end)
end
function F.MoreAuctionRecipes()
  local api=available(); if not api then return false end
  if not query or not query.owned then
    F.Say('The browse search changed or cannot be tracked. Use Full AH scan to refresh the market.'); return false
  end
  if query.waiting then F.Say('Waiting for the current recipe page.'); return false end
  if F.Safe(api.HasFullBrowseResults)==true then F.Say('All recipe browse pages have arrived.'); return false end
  if not api.RequestMoreBrowseResults or F.Safe(api.HasFullBrowseResults)~=false then
    F.Say('More browse pages are unavailable.'); return false
  end
  if query.paused then query.paused=false; query.started=time(); query.ticks=0 end
  query.waiting=true
  local ok=pcall(api.RequestMoreBrowseResults)
  if not ok then query.waiting=false; F.Say('The next recipe page could not be requested.'); return false end
  queueNextPage()
  return true
end
function F.ObserveAuctionRecipes()
  if not F.db or not F.IsAuctionHouseOpen() then F.ClearAuctionLearning(); return end
  local results=C_AuctionHouse and F.Safe(C_AuctionHouse.GetBrowseResults)
  if type(results)~='table' then return end
  for _,listing in ipairs(results) do
    local id=listing.itemKey and listing.itemKey.itemID
    if identifier(id) then
      F.auctionRecipes[id]=nil
      -- A newer browse answer supersedes this item's older snapshot, including
      -- owner-only/no-buyout answers. Unrelated material queries leave it intact.
      if F.fullScanRecipes[id] then supersededSnapshotOffers[id]=true end
      if not listing.containsOwnerItem and not listing.containsAccountItem and positive(listing.minPrice) then
        local name,_,_,_,_,_,_,_,_,_,_,class,subclass=F.ItemInfo(id)
        -- Keep unloaded item metadata pending, with the actual browse timestamp.
        -- GET_ITEM_INFO_RECEIVED can resolve it without making an old price fresh.
        if not class or class==9 then
          F.auctionRecipes[id]={id=id,name=name,price=listing.minPrice,seen=time(),subclass=subclass}
          if not name then F.ItemName(id) end
        end
      end
    end
  end
  if query then query.waiting=false; query.complete=F.Safe(C_AuctionHouse.HasFullBrowseResults)==true end
  queueNextPage()
  summary=nil
end
local function itemSpells(id)
  local ids,seen,hints={}, {}, {}
  local function add(spellID,hint)
    if identifier(spellID) then
      if not seen[spellID] then ids[#ids+1]=spellID; seen[spellID]=true; hints[spellID]=hint==true
      elseif not hint then hints[spellID]=false end
    end
  end
  if F.CatalogueRecipeIDsForItem then
    for _,recipeID in ipairs(F.CatalogueRecipeIDsForItem(id) or {}) do add(recipeID) end
  end
  local getSpell=C_Item and C_Item.GetItemSpell or GetItemSpell
  if getSpell then
    local ok,_,spellID=pcall(getSpell,id)
    if ok then add(spellID) end
  end
  local tooltip=C_TooltipInfo and F.Safe(C_TooltipInfo.GetItemByID,id)
  local types=Enum and Enum.TooltipDataLineType
  local known=false
  for _,line in ipairs(type(tooltip)=='table' and tooltip.lines or {}) do
    if types and ((types.LearnableSpell and line.type==types.LearnableSpell)
        or (types.ItemSpellTriggerLearn and line.type==types.ItemSpellTriggerLearn)) then
      -- Some clients supply this field, others do not. It is only a candidate
      -- until the recipe, profession and schematic independently validate it.
      add(line.spellID)
    end
    if type(ITEM_SPELL_KNOWN)=='string' and (line.leftText==ITEM_SPELL_KNOWN or line.rightText==ITEM_SPELL_KNOWN) then known=true end
  end
  if F.CatalogueRecipeHintsForItem then
    for _,recipeID in ipairs(F.CatalogueRecipeHintsForItem(id) or {}) do add(recipeID,true) end
  end
  return ids,known,hints
end
local function recipeForSpell(id,subclass,references)
  local api=C_TradeSkillUI
  if not ownSource(api) then
    return nil,'Close the linked, guild or NPC crafting source before checking learned status'
  end
  local previous=F.db.recipes[id]
  references=references or (F.CatalogueRecipes and F.CatalogueRecipes())
  local reference=references and references[id]
  local referenceNewer=newerKnowledge(reference,previous)
  local info=api and F.Safe(api.GetRecipeInfo,id)
  if info~=nil then
    if type(info)~='table' or info.recipeID~=id or type(info.learned)~='boolean' then
      return nil,'Item spell is not a verified crafting recipe'
    end
    if info.learned then return nil,'known' end
    if info.disabled or info.isRecraft or info.isSalvageRecipe or info.isDummyRecipe or info.isGatheringRecipe then
      return nil,'Unsupported crafting operation'
    end
  else
    -- A current own-character API answer takes precedence over an earlier
    -- import. While that API is inactive, only newer verified knowledge can
    -- overturn a saved known recipe; database references cannot do so.
    if referenceNewer then
      if reference.learned then return nil,'known' end
    elseif (previous and previous.learned==true and previous.observedBuild==F.Build())
        or (reference and reference.learned==true and reference.observedBuild==F.Build()) then return nil,'known' end
  end
  local owner=api and F.Safe(api.GetProfessionInfoByRecipeID,id)
  local profession=F.ProfessionIDFromInfo(owner)
  if owner~=nil and (not profession or (subclasses[subclass] and subclasses[subclass]~=profession)) then
    return nil,'Recipe profession is not verified'
  end
  if info==nil or owner==nil then
    -- An inactive profession can stop exposing recipe details at the AH. Its
    -- previously verified import remains evidence for this exact spell ID,
    -- provided no current API answer contradicts its identity or knowledge.
    local function validCached(cached)
      if not (cached and cached.id==id
          and ((cached.reader=='modern' and cached.professionVerified==true) or cached.referenceOnly==true)
          and (cached.observedBuild==F.Build() or (cached==reference and cached.databaseReference==true and cached.referenceOnly==true))
          and (cached.learned~=true or (info and info.learned==false)) and not cached.problem
          and identifier(cached.profession) and identifier(cached.output) and positive(cached.made)
          and type(cached.reagents)=='table' and #cached.reagents>0
          and (not profession or cached.profession==profession)
          and (not subclasses[subclass] or cached.profession==subclasses[subclass])) then return false end
      for _,reagent in ipairs(cached.reagents) do
        if not identifier(reagent.itemID) or not positive(reagent.qty) then return false end
      end
      return true
    end
    local cached=referenceNewer and validCached(reference) and reference
      or (validCached(previous) and previous) or (validCached(reference) and reference)
    if cached then
      if not ownSource(api) or api~=C_TradeSkillUI then return nil,'Crafting source changed while loading' end
      if info and info.learned==false then
        local copy={}; for key,value in pairs(cached) do copy[key]=value end
        copy.learned=false; return copy
      end
      return cached
    end
    return nil,'Recipe data unavailable; open its profession once to import it automatically'
  end
  local schematic=F.Safe(api.GetRecipeSchematic,id,false)
  if type(schematic)~='table' or schematic.recipeID~=id then return nil,'Recipe schematic identity is not verified' end
  if schematic.isRecraft or schematic.isSalvageRecipe or schematic.isDummyRecipe or schematic.isGatheringRecipe then
    return nil,'Unsupported crafting operation'
  end
  local recipeTypes=Enum and Enum.TradeskillRecipeType
  if schematic.recipeType~=nil and (not recipeTypes or recipeTypes.Item==nil or schematic.recipeType~=recipeTypes.Item) then
    return nil,'Unsupported non-item crafting operation'
  end
  if not identifier(schematic.outputItemID) or not identifier(schematic.quantityMin)
      or type(schematic.reagentSlotSchematics)~='table' then return nil,'Recipe ingredients or output are unavailable' end
  local reagents={}
  for _,slot in ipairs(schematic.reagentSlotSchematics) do
    if type(slot)~='table' then return nil,'Recipe ingredient data is unavailable' end
    local quantity=slot.quantityRequired
    if quantity~=nil and (type(quantity)~='number' or quantity<0 or quantity~=math.floor(quantity)) then
      return nil,'Unsupported ingredient quantity'
    end
    local basic=slot.reagentType==nil or (Enum and Enum.CraftingReagentType and slot.reagentType==Enum.CraftingReagentType.Basic)
    if positive(quantity) then
      local options=slot.reagents
      if not basic or type(options)~='table' or #options~=1 or type(options[1])~='table'
          or not identifier(options[1].itemID) or positive(options[1].currencyID) then
        return nil,'Unsupported ingredient choice or currency'
      end
      local slotTypes=Enum and Enum.TradeskillSlotDataType
      if slot.dataSlotType~=nil and (not slotTypes or slotTypes.Reagent==nil or slot.dataSlotType~=slotTypes.Reagent) then
        return nil,'Unsupported ingredient slot type'
      end
      if type(slot.variableQuantities)=='table' and #slot.variableQuantities>0 then return nil,'Unsupported variable ingredient quantity' end
      reagents[#reagents+1]={itemID=options[1].itemID,qty=quantity}
    elseif slot.required then return nil,'Unsupported required ingredient slot' end
  end
  if #reagents==0 then return nil,'Recipe ingredients are unavailable' end
  local _,_,_,_,_,_,_,_,_,_,_,_,_,bind=F.ItemInfo(schematic.outputItemID)
  if bind==1 or bind==4 then return nil,'Crafted output cannot be auctioned' end
  local after=F.Safe(api.GetProfessionInfoByRecipeID,id)
  if not ownSource(api) or api~=C_TradeSkillUI or F.ProfessionIDFromInfo(after)~=profession then
    return nil,'Recipe profession or crafting source changed while loading'
  end
  local recipe={id=id,name=info.name or schematic.name or ('Recipe '..id),profession=profession,
    output=schematic.outputItemID,made=schematic.quantityMin,reagents=reagents,learned=false,
    professionVerified=true,reader='modern',observedBuild=F.Build(),observedAt=time()}
  if previous and previous.profession==profession and previous.output==recipe.output and previous.observedBuild==recipe.observedBuild then
    for _,key in ipairs({'trainerAvailable','trainerSeen','trainerName','trainingCost'}) do recipe[key]=previous[key] end
  end
  return recipe
end
local function mappedRecipe(listing,references)
  local name,_,_,_,_,_,_,_,_,_,_,class,subclass=F.ItemInfo(listing.id)
  if class~=9 then return nil,class and 'not_recipe' or 'Item information is loading' end
  listing.name=name or listing.name; listing.subclass=subclass
  local ids,known,hints=itemSpells(listing.id)
  if known then return nil,'known' end
  local result,reason
  for _,id in ipairs(ids) do
    local recipe,why=recipeForSpell(id,subclass,references)
    if why=='known' then return nil,'known' end
    if recipe then
      if result and result.id~=recipe.id then return nil,'Item teaches multiple possible recipes; mapping is unverified' end
      if hints[id] then
        local copy={}; for key,value in pairs(recipe) do copy[key]=value end
        copy.databaseMapping=true; copy.referenceOnly=true; recipe=copy
      end
      result=recipe
    else reason=reason or why end
  end
  return result,reason or 'No verified item-to-recipe spell mapping'
end
local function learningAllowed(listing,recipe)
  local actual=F.currentProfessionsComplete and F.currentProfessions and F.currentProfessions[recipe.profession]
  local chosen=F.SkillLevel(recipe.profession)
  if not positive(actual) then return false,'Current profession skill has not been detected' end
  if not positive(chosen) then return false,'Choose your profession skill level in Character setup' end
  local required=F.RequiredSkill(recipe)
  -- Database minimums can conservatively hide recipes beyond this skill. They
  -- cannot establish that this character is allowed to learn a recipe.
  local referenceRequired=recipe.databaseReference and tonumber(recipe.databaseRequiredSkill)
  if referenceRequired and (referenceRequired>actual or referenceRequired>chosen) then return false,'above' end
  if required and (required>actual or required>chosen) then return false,'above' end
  if not required and chosen<actual then return false,'Minimum skill unknown at your lower skill preview; use detected levels' end
  if recipe.databaseReference then return false,'Recipe Registry reference; current recipe details and learning requirements need game confirmation' end
  if recipe.databaseMapping then return false,'Recipe Registry item association; confirm this item teaches the displayed craft' end
  if recipe.learned~=false then return false,'Learning status is not verified for this character; open the profession' end
  if not listing then
    if recipe.trainerAvailable and fresh(recipe.trainerSeen,3600) and required then return true end
    return false,'Check where this recipe is learned and its current requirements'
  end
  local usable=C_Item and F.Safe(C_Item.IsUsableItem,listing.id)
  if usable~=true then return false,usable==false and 'The game does not currently allow you to learn this item' or 'The game has not confirmed that this item can be learned' end
  recipe.observedSkill=actual
  return true
end
local function checkedQuote(id,quantity,reagent)
  return F.ForecastQuote(id,quantity,reagent)
end

local function evaluateRecipe(recipe,listing)
  if not F.db.selectedProfessions[recipe.profession] or (F.filter and F.filter~=recipe.profession)
      or (F.currentProfessionsComplete and not F.currentProfessions[recipe.profession]) then return nil,'profession' end
  local canLearn,learningReason=learningAllowed(listing,recipe)
  if learningReason=='above' then return nil,'above' end
  -- The record comes from an exact client recipe ID, its own profession and a
  -- complete schematic. No name matching or inferred teach-spell conversion.
  if listing and not recipe.referenceOnly then F.db.recipes[recipe.id]=recipe end
  local settings={crafts=1,cut=F.db.cut,duration=F.db.duration,failures=F.db.failures}
  local row=F.Evaluate(recipe,settings,checkedQuote,F.Deposit)
  local ingredientEstimated=row.estimated
  if recipe.databaseReference or recipe.databaseMapping then
    row.databaseReference=recipe.databaseReference==true; row.databaseMapping=recipe.databaseMapping==true
    row.referenceSource=recipe.source or recipe.databaseSource or 'Recipe Registry Forever'; row.estimated=true
  end
  if listing then
    row.acquisition='auction'; row.acquisitionItemID=listing.id; row.acquisitionName=listing.name or ('Item '..listing.id)
    local cost,source,_,evidence=F.BatchQuote(listing.id,1,nil)
    row.acquisitionChecked=cost~=nil and evidence and evidence.kind=='depth' or false
    row.acquisitionPrice=row.acquisitionChecked and cost or listing.price
    row.acquisitionPriceSource=row.acquisitionChecked and ('Checked purchase: '..(source or 'current listings'))
      or listing.source or 'Browse minimum estimate; check the listing before buying'
    row.fromFullScan=listing.snapshot==true
  else
    row.acquisition='catalogue'; row.acquisitionPriceSource='No recipe purchase price observed; find a trainer or recipe source'
    row.acquisitionChecked=false
  end
  -- Acquisition is deliberately display-only. It never changes adjusted craft
  -- profit, profitability flags, or ordering.
  row.canLearn=canLearn; row.pending={}
  if not canLearn then row.pending[#row.pending+1]=learningReason end
  for _,missing in ipairs(row.missing or {}) do row.pending[#row.pending+1]=missing end
  if row.needsDeposit then row.pending[#row.pending+1]=row.depositSource or 'Output deposit needs a game quote' end
  if ingredientEstimated then row.pending[#row.pending+1]='Ingredient quantities need current auction checks' end
  local demand=AHledgerAPI and F.Safe(AHledgerAPI.GetPrice,recipe.output)
  if type(demand)=='table' and not demand.snapshot and fresh(demand.updated,F.db.maxAge*86400)
      and type(demand.soldPerDay)=='number' and demand.soldPerDay>=0 and demand.soldPerDay<math.huge then
    row.demandPerDay=demand.soldPerDay; row.demandSource='AHledger estimated units sold/day'
  end
  row.profitCandidate=canLearn and row.adjusted~=nil and row.adjusted>0 and not row.estimated and #row.pending==0
  row.forecastProfitable=row.adjusted~=nil and row.adjusted>0
  row.candidate=row.profitCandidate and row.demandPerDay~=nil and row.demandPerDay>=1
  if row.candidate then row.flag='worth_learning'; row.status='Profitable craft; estimated demand supports learning'
  elseif row.profitCandidate then
    row.flag='profit_candidate'
    row.status=row.demandPerDay==nil and 'Profitable craft; demand unknown' or 'Profitable craft; estimated demand is low'
  elseif #row.pending>0 then row.flag='needs_check'; row.status='Needs checking: '..table.concat(row.pending,'; ')
  else row.flag='not_profitable'; row.status='Crafting is not profitable at the checked prices' end
  return row
end
local function evaluate(listing,references)
  local recipe,reason=mappedRecipe(listing,references)
  if not recipe then return nil,reason end
  return evaluateRecipe(recipe,listing)
end
local function catalogueRecipe(id,catalogue)
  catalogue=catalogue or (F.CatalogueRecipes and F.CatalogueRecipes()) or {}
  local recipe=catalogue[id]
  local databaseReference=recipe and recipe.databaseReference==true and recipe.referenceOnly==true
  if not recipe or (recipe.observedBuild~=F.Build() and not databaseReference) or recipe.problem then return nil,'Catalogue crafting data unavailable for this build' end
  local observed=F.db.recipes[id]
  local referenceNewer=newerKnowledge(recipe,observed)
  if recipe.learned==true or (not referenceNewer and observed and observed.learned==true and observed.observedBuild==F.Build()) then return nil,'known' end
  -- A character observation can establish learning status and trainer access;
  -- reference data by itself is never turned into a character-known recipe.
  if observed and observed.observedBuild==F.Build() and observed.profession==recipe.profession and observed.output==recipe.output then
    local merged={}; for key,value in pairs(recipe) do merged[key]=value end
    for _,key in ipairs({'trainerAvailable','trainerSeen','trainerName','trainingCost'}) do merged[key]=observed[key] end
    if not referenceNewer and type(observed.learned)=='boolean' then merged.learned=observed.learned end
    recipe=merged
  end
  return recipe
end
function F.EvaluateCatalogueLearning(recipeID)
  if not F.db then return end
  local recipe,reason=catalogueRecipe(recipeID)
  if not recipe then return nil,reason end
  F.priceCache={}
  return evaluateRecipe(recipe,nil)
end
function F.CatalogueLearningRows(excluded,catalogue)
  local rows={}
  if not F.db or not F.CatalogueRecipes then return rows end
  F.priceCache={}
  catalogue=catalogue or F.CatalogueRecipes() or {}
  for id in pairs(catalogue) do
    if not excluded or not excluded[id] then
      local recipe=catalogueRecipe(id,catalogue)
      local row=recipe and evaluateRecipe(recipe,nil)
      if row then rows[#rows+1]=row end
    end
  end
  return rows
end
function F.EvaluateAuctionLearning(itemID)
  if not F.db then return end
  local open=F.IsAuctionHouseOpen()
  local listing=allOffers(open)[itemID]
  if not listing then return nil,'Recipe listing is missing or expired; run a full AH scan' end
  F.priceCache={}
  return evaluate(listing,F.CatalogueRecipes and F.CatalogueRecipes() or {})
end
function F.AuctionLearningRows(references)
  local rows={}
  if not F.db then return rows end
  local offers=allOffers(F.IsAuctionHouseOpen())
  local stats={observed=0,mapped=0,unmapped=0,known=0,otherProfession=0,above=0,needsCheck=0,profitable=0,candidates=0,forecasts=0}
  F.priceCache={}
  local catalogue=references or (F.CatalogueRecipes and F.CatalogueRecipes() or {})
  local ids={}; for id in pairs(offers) do ids[#ids+1]=id end; table.sort(ids)
  for _,id in ipairs(ids) do
    local listing=offers[id]
    if listing then
      stats.observed=stats.observed+1
      local row,reason=evaluate(listing,catalogue)
      if row then
        rows[#rows+1]=row; stats.mapped=stats.mapped+1
        if #row.pending>0 then stats.needsCheck=stats.needsCheck+1 end
        if row.profitCandidate then stats.profitable=stats.profitable+1 end
        if row.candidate then stats.candidates=stats.candidates+1 end
        if row.forecastProfitable then stats.forecasts=stats.forecasts+1 end
      elseif reason=='known' then stats.known=stats.known+1
      elseif reason=='profession' then stats.otherProfession=stats.otherProfession+1
      elseif reason=='above' then stats.above=stats.above+1
      else
        stats.unmapped=stats.unmapped+1; stats.firstUnmapped=stats.firstUnmapped or reason
        local profession=subclasses[listing.subclass]
        if profession and F.db.selectedProfessions[profession] and (not F.filter or F.filter==profession) then
          local why=reason or 'Crafting data unavailable; open this profession to import its recipes'
          local recipe={id=-id,name=listing.name or ('Recipe item '..id),profession=profession,learned=false,made=1,reagents={},problem=why}
          local pending=F.Evaluate(recipe,{crafts=1,cut=F.db.cut,duration=F.db.duration,failures=F.db.failures},F.Quote,F.Deposit)
          pending.acquisition='auction'; pending.acquisitionItemID=id; pending.acquisitionName=recipe.name
          pending.acquisitionPrice=listing.price; pending.acquisitionPriceSource=listing.source or 'Browse minimum estimate'
          pending.pending={why}; pending.status=why; pending.flag='needs_check'; pending.canLearn=false
          rows[#rows+1]=pending
        end
      end
    end
  end
  table.sort(rows,function(a,b)
    if a.profit~=b.profit then return (a.profit or -math.huge)>(b.profit or -math.huge) end
    return a.acquisitionItemID<b.acquisitionItemID
  end)
  summary=stats
  return rows
end
function F.AuctionLearningStatus()
  if not F.db then return 'Open the AH and run a full scan to compare recipe purchases.' end
  if not summary then F.AuctionLearningRows() end
  local s=summary or {}
  local lines={string.format('AH recipes: %d observed; %d mapped; %d profitable forecasts; %d need checks.',s.observed or 0,s.mapped or 0,s.forecasts or 0,s.needsCheck or 0)}
  if (s.unmapped or 0)>0 then lines[#lines+1]=s.unmapped..' could not be mapped safely: '..(s.firstUnmapped or 'client recipe data unavailable')..'. No spell IDs are guessed.' end
  if (s.known or 0)>0 then lines[#lines+1]=s.known..' already known.' end
  if (s.otherProfession or 0)>0 then lines[#lines+1]=s.otherProfession..' belong to other professions or your current filter.' end
  if (s.above or 0)>0 then lines[#lines+1]=s.above..' exceed your current or selected profession skill and are excluded.' end
  if query and query.owned then
    lines[#lines+1]=query.complete and 'All recipe browse pages received.' or (query.paused and 'Scan paused; use Full AH scan to refresh the market.' or 'Scanning all recipe browse pages; keep the AH open.')
  elseif query then lines[#lines+1]='Another browse search took over, or this client cannot track it. Use Full AH scan to refresh the market.' end
  lines[#lines+1]='Craft profit excludes the displayed recipe purchase price. Demand is an AHledger estimate, not guaranteed sales.'
  return table.concat(lines,'\n')
end
local events=CreateFrame('Frame')
for _,event in ipairs({'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','GET_ITEM_INFO_RECEIVED',
  'AUCTION_HOUSE_CLOSED','PLAYER_INTERACTION_MANAGER_FRAME_HIDE','SPELLS_CHANGED','SKILL_LINES_CHANGED',
  'COMMODITY_SEARCH_RESULTS_UPDATED','COMMODITY_SEARCH_RESULTS_ADDED','ITEM_SEARCH_RESULTS_UPDATED','ITEM_SEARCH_RESULTS_ADDED'}) do events:RegisterEvent(event) end
local metadataRefreshPending=false
local function queueMetadataRefresh()
  if metadataRefreshPending or not C_Timer or not C_Timer.After then return end
  metadataRefreshPending=true
  C_Timer.After(0.5,function()
    metadataRefreshPending=false; summary=nil
    if F.worthLearning and F.window and F.window:IsShown() then refreshUI() end
  end)
end
events:SetScript('OnEvent',function(_,event,interaction)
  if event=='AUCTION_HOUSE_CLOSED' or (event=='PLAYER_INTERACTION_MANAGER_FRAME_HIDE' and Enum and Enum.PlayerInteractionType
      and interaction==Enum.PlayerInteractionType.Auctioneer) then F.ClearAuctionLearning(); refreshUI(); return end
  if not F.db then return end
  local browseEvent=event=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED'
  if browseEvent then F.ObserveAuctionRecipes(); refreshUI(); return end
  if event=='GET_ITEM_INFO_RECEIVED' then
    if F.worthLearning and (next(F.auctionRecipes) or next(F.fullScanRecipes)) then queueMetadataRefresh() end
    return
  end
  if event=='SPELLS_CHANGED' or event=='SKILL_LINES_CHANGED' then summary=nil; refreshUI() end
end)
