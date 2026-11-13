-- Candidate discovery must never fabricate a character's learned recipes or
-- import Classic quantities/ranks into the Forever profit calculations.
return function(F,eq)
  local globals={}
  for _,key in ipairs({'C_TradeSkillUI','C_Timer','C_Item','C_TooltipInfo','GetItemSpell','Enum','time',
      'RecipeRegistryRecipeMetadata','GetBuildInfo','C_Spell','CreateFrame','EventRegistry'}) do
    globals[key]={value=_G[key]}
  end
  local now,build=4000,'70862'
  time=function() return now end
  Enum={CraftingReagentType={Basic=0,Optional=1},TradeskillRecipeType={Item=1,Enchant=3},
    TradeskillSlotDataType={Reagent=1,Currency=3},TooltipDataLineType={LearnableSpell=6,ItemSpellTriggerLearn=38}}
  local timers={}
  local eventFrame
  CreateFrame=function()
    eventFrame={events={},scripts={}}
    eventFrame.RegisterEvent=function(self,event) self.events[event]=true end
    eventFrame.SetScript=function(self,script,callback) self.scripts[script]=callback end
    return eventFrame
  end
  EventRegistry=nil
  C_Timer={After=function(_,callback) timers[#timers+1]=callback end}
  local records,list,linked,reads={}, {},false,0
  C_TradeSkillUI={
    IsTradeSkillLinked=function() return linked end,
    IsTradeSkillGuild=function() return false end,
    IsNPCCrafting=function() return false end,
    GetAllRecipeIDs=function() return list end,
    GetRecipeInfo=function(id)
      reads=reads+1
      local r=records[id]; if not r or r.noInfo then return nil end
      return {recipeID=r.wrongID or id,name='Recipe '..id,learned=r.learned,disabled=r.disabled}
    end,
    GetProfessionInfoByRecipeID=function(id)
      local r=records[id]; if r and not r.noOwner then return {professionID=185} end
    end,
    GetRecipeSchematic=function(id)
      local r=records[id]; if not r then return nil end
      return {recipeID=r.wrongSchematic or id,name='Recipe '..id,outputItemID=250065,
        quantityMin=r.made or 1,recipeType=r.recipeType or 1,isRecraft=r.isRecraft,
        reagentSlotSchematics=r.slots or {
          {reagentType=0,quantityRequired=2,reagents={{itemID=5471}}},
          {reagentType=0,quantityRequired=3,reagents={{itemID=2692}}},
        }}
    end,
  }
  local L={db={recipes={}},currentProfessionsComplete=true,currentProfessions={[185]=240},
    Build=function() return build end,ProfessionIDFromInfo=F.ProfessionIDFromInfo}
  L.Safe=function(fn,...)
    if type(fn)~='function' then return end
    local ok,value=pcall(fn,...); if ok then return value end
  end
  assert(loadfile('MobAuction/CatalogueData.lua'))('MobAuction',L)
  eq(#L.catalogueCandidates>2000,true,'catalogue ships a substantial finite list of discovery candidates')
  local previous=0
  for _,id in ipairs(L.catalogueCandidates) do
    assert(type(id)=='number' and id>previous and id==math.floor(id),'candidate IDs must be unique sorted integers')
    previous=id
  end
  assert(loadfile('MobAuction/Catalogue.lua'))('MobAuction',L)
  local function flush()
    local count=0
    while #timers>0 do
      count=count+1; assert(count<500,'catalogue timer did not settle')
      local timer=table.remove(timers,1); timer()
    end
  end
  local function reset()
    L.db={recipes={}}; L.catalogueCandidates={}; records={}; list={}; reads=0; linked=false
    timers={}; now=now+10
  end
  reset()
  records[1250142]={learned=true}; records[101]={learned=false}; records[102]={noInfo=true}
  -- Even a broken, old import still discovers the exact new Forever spell ID.
  L.db.recipes[1250142]={id=1250142,profession=356,learned=true,observedBuild='old'}
  list={101,102}
  eq(next(L.CatalogueRecipes()),nil,'unverified saved imports do not become reference recipe facts')
  eq(L.RefreshCatalogue('login'),true,'catalogue starts bounded discovery')
  eq(reads,0,'discovery never blocks the caller with synchronous recipe API walks')
  flush()
  local recipes=L.CatalogueRecipes()
  eq(recipes[1250142].profession,185,'live owner repairs the reference identity without modifying a corrupt import')
  eq(L.db.recipes[1250142].profession,356,'reference collection cannot overwrite character import data')
  eq(recipes[1250142].reagents[1].qty,2,'Savory Stag Sliders uses current-client two-meat schematic')
  eq(recipes[1250142].reagents[2].qty,3,'Savory Stag Sliders uses current-client three-spice schematic')
  eq(recipes[1250142].learned,true,'current exact own-character recipe info can prove learned status')
  eq(recipes[1250142].observedSkill,240,'known reference captures independently detected current profession rank')
  eq(recipes[101].learned,false,'current recipe API can independently prove unlearned status')
  eq(recipes[102].learned,nil,'missing recipe info is unknown knowledge, never implicitly unlearned')
  eq(recipes[101].referenceOnly,true,'research recipes remain explicitly separate from character imports')
  eq(L.db.catalogue.recipes[101].learned,nil,'persisted reference data never stores inferred character knowledge')
  eq(L.db.recipes[101],nil,'research data is not inserted into the learned/imported recipe map')
  eq(L.CatalogueStatus().validated,3,'catalogue coverage counts verified transformations')
  eq(L.CatalogueStatus().complete,false,'finished candidate checks never claim all Forever recipes are covered')
  eq(L.CatalogueStatus().running,false,'finite catalogue walk finishes')
  local priorReads=reads
  L.RefreshCatalogue('login'); flush()
  eq(reads,priorReads,'repeated login refresh does not recheck the full historical seed list')
  recipes[101].reagents[1].qty=999
  eq(L.CatalogueRecipes()[101].reagents[1].qty,2,'callers cannot mutate persisted reference reagent quantities')
  L.db.recipes[1250142]={id=1250142,profession=185,reader='modern',professionVerified=true,learned=false,
    observedBuild=build,observedAt=now-100,output=250065,made=1,reagents={{itemID=5471,qty=1}},
    trainerAvailable=true,trainerSeen=now-100}
  eq(L.CatalogueRecipes()[1250142].learned,true,'fresh client knowledge supersedes an older same-build imported knowledge snapshot')
  eq(L.CatalogueRecipes()[1250142].reagents[1].qty,2,'fresh client quantities supersede older same-build imported quantities')
  eq(L.CatalogueRecipes()[1250142].trainerAvailable,true,'matching trainer evidence survives newer reference facts')
  eq(L.db.recipes[1250142].learned,false,'reference precedence still leaves character imports untouched')

  reset(); L.catalogueCandidates={11,12,13,14,15,16,17,18,19,20}
  records[11]={learned=false,wrongID=999}
  records[12]={learned=false,wrongSchematic=999}
  records[13]={learned=false,noOwner=true}
  records[14]={learned=false,made=0}
  records[15]={learned=false,recipeType=3}
  records[16]={learned=false,slots={{reagentType=0,quantityRequired=1,reagents={{currencyID=1}}}}}
  records[17]={learned=false,slots={{reagentType=0,quantityRequired=1,reagents={{itemID=1},{itemID=2}}}}}
  records[18]={learned=false,slots={{reagentType=1,quantityRequired=1,reagents={{itemID=1}}}}}
  records[19]={learned=false,slots={{reagentType=0,quantityRequired=0,required=true,reagents={{itemID=1}}}}}
  records[20]={learned=false,slots={{reagentType=0,quantityRequired=1,reagents={{itemID=1}},variableQuantities={{quantity=2}}}}}
  L.RefreshCatalogue('login'); flush()
  eq(next(L.CatalogueRecipes()),nil,'identity mismatch, missing owner, unsupported outputs and ambiguous inputs cannot be priced')
  eq(L.CatalogueStatus().unavailable,10,'unsupported and unavailable candidates remain counted as unresolved')

  reset()
  for id=1,30 do L.catalogueCandidates[#L.catalogueCandidates+1]=id; records[id]={learned=false} end
  L.RefreshCatalogue('login')
  table.remove(timers,1)()
  eq(reads,12,'one scheduled callback performs at most twelve recipe reads')
  eq(L.CatalogueStatus().pending,18,'larger catalogues yield between bounded batches')
  L.CancelCatalogueRefresh(); flush()
  eq(reads,12,'cancelled work cannot continue through an already scheduled callback')
  L.RefreshCatalogue('login'); flush()
  eq(reads,30,'resuming processes remaining candidates without redoing finished checks')
  eq(L.CatalogueStatus().validated,30,'all supported candidates are gathered across batches')

  reset(); L.catalogueCandidates={1}; records[1]={learned=false}; linked=true
  L.RefreshCatalogue('login'); flush()
  eq(reads,0,'linked profession sources cannot establish character knowledge or reference entries')
  eq(L.CatalogueStatus().paused,true,'linked sources pause the pending catalogue instead of discarding IDs')
  linked=false; L.RefreshCatalogue('profession'); flush()
  eq(L.CatalogueRecipes()[1].learned,false,'own profession refresh resumes previously paused data collection')

  reset(); L.catalogueCandidates={1}; records[1]={learned=false,noOwner=true}
  L.RefreshCatalogue('login'); flush()
  eq(L.CatalogueStatus().validated,0,'unavailable owner metadata remains pending')
  records[1].noOwner=false; now=now+10
  L.RefreshCatalogue('profession'); flush()
  eq(L.CatalogueStatus().validated,1,'opening a profession retries previously unavailable schematics')
  priorReads=reads; L.RefreshCatalogue('profession'); flush()
  eq(reads,priorReads,'frequent profession events are coalesced instead of restarting every candidate')
  build='new-build'
  eq(next(L.CatalogueRecipes()),nil,'a client build change invalidates prior reference ingredient data')
  L.RefreshCatalogue('login'); flush()
  eq(L.CatalogueRecipes()[1].observedBuild,'new-build','recipe data can be reverified for the new client build')

  -- A spell in item use data can be a generic Learning wrapper. Only exact
  -- current references can be returned as a mapping; names never supply IDs.
  C_Item={GetItemSpell=function(id) return 'Learning',id==900 and 1 or 483 end}
  C_TooltipInfo={GetItemByID=function(id)
    return {lines=id==902 and {{type=6,spellID=1}} or {{leftText='Recipe 1'}}}
  end}
  eq(L.CatalogueRecipeIDsForItem(900)[1],1,'exact current item effect and verified schematic produce a recipe ID')
  eq(#L.CatalogueRecipeIDsForItem(901),0,'a generic Learning use spell never maps by item name')
  eq(L.CatalogueRecipeIDsForItem(902)[1],1,'typed current learnable-spell tooltip can resolve a wrapper item')
  flush()
  eq(L.CatalogueRecipes()[483],nil,'failed generic wrapper lookup does not fabricate a reference recipe')

  -- A previous session may preserve transformation facts, never knowledge.
  L.db.catalogue.recipes[1].learned=false
  L.db={recipes={},catalogue=L.db.catalogue}
  eq(L.CatalogueRecipes()[1].learned,nil,'same-build persisted reference has unknown knowledge in a new session')
  eq(type(L.CatalogueStatusText()),'string','catalogue provides a readable coverage status')
  reset(); L.db.catalogue={build=build,recipes={[1]=42,[2]={id=2}}}
  eq(next(L.CatalogueRecipes()),nil,'malformed persisted reference entries are discarded safely')
  eq(#L.CatalogueRecipeHintsForItem(900),0,'missing optional Registry data has an empty safe mapping adapter')

  reset(); build='70862'
  GetBuildInfo=function() return '1.60.1','70862' end
  C_Spell={GetSpellName=function(id) return id==1250142 and 'Savory Stag Sliders' or nil end}
  RecipeRegistryRecipeMetadata={schemaVersion=1,flavor='forever',metadataVersion='forever-1.60.1.70790',recipesBySpellId={
    [1250142]={profession='cooking',createdItemId=250065,recipeItemId=250173,requiredSkill=225,
      reagents={{itemId=5471,count=2},{itemId=2692,count=3}}},
    [2]={profession='alchemy',createdItemId=100,removed=true,reagents={{itemId=1,count=1}}},
    [3]={profession='engineering',createdItemId=100,bopOutput=true,reagents={{itemId=1,count=1}}},
    [4]={profession='tailoring',createdItemId=100,reagents={{itemId=1,count=0}}},
    [5]={profession='unknown_profession',createdItemId=100,reagents={{itemId=1,count=1}}},
    [6]={profession='first_aid',createdItemId=100,createdCount=5,reagents={{itemId=1,count=1}}},
  }}
  local reference=L.CatalogueRecipes()[1250142]
  eq(reference.name,'Savory Stag Sliders','optional Forever database uses current client spell names')
  eq(reference.databaseReference,true,'Registry facts are explicitly labelled database references')
  eq(reference.sourceBuild,'70790','database forecasts preserve their actual source build')
  eq(reference.observedBuild,nil,'older database facts are never stamped as observed in the current client')
  eq(reference.professionVerified,false,'database profession assignment is not mislabelled client verification')
  eq(reference.learned,nil,'reference existence makes no claim about character knowledge')
  eq(reference.made,1,'Registry omitted createdCount means the documented default single output')
  eq(reference.reagents[1].qty,2,'Forever reference preserves two Stag Meat per sliders craft')
  eq(reference.databaseRequiredSkill,225,'database skill hint stays separate from verified character requirements')
  eq(L.CatalogueRecipes()[6].made,5,'nondefault minimum output counts survive the Registry adapter')
  eq(L.CatalogueStatus().validated,0,'database forecasts never inflate current-client validated coverage')
  eq(L.CatalogueStatus().references,2,'removed, bound and malformed transformations are excluded from database forecasts')
  eq(L.CatalogueStatus().providerRecipes,6,'provider total is reported separately from supported forecast count')
  eq(L.CatalogueRecipeHintsForItem(250173)[1],1250142,'Registry recipe-item association is exposed as an unverified hint')
  eq(#L.CatalogueRecipeIDsForItem(250173),0,'database association does not impersonate a current client item effect')
  L.RefreshCatalogue('login'); flush()
  eq(L.CatalogueRecipes()[1250142].databaseReference,true,'inactive profession APIs preserve labelled database research')
  eq(L.db.recipes[1250142],nil,'optional database integration never inserts character recipes')
  records[1250142]={learned=false}; now=now+10
  L.RefreshCatalogue('profession'); flush()
  eq(L.CatalogueRecipes()[1250142].databaseReference,nil,'current client schematic supersedes historical reference facts')
  eq(L.CatalogueRecipes()[1250142].observedBuild,'70862','validated current schematic reports the actual current build')
  eq(L.CatalogueStatus().validated,1,'verified coverage grows only after a current-client observation')
  RecipeRegistryRecipeMetadata={schemaVersion=1,flavor='tbc',metadataVersion='forever-1.60.1.70790',
    recipesBySpellId=RecipeRegistryRecipeMetadata.recipesBySpellId}
  reset()
  eq(next(L.CatalogueRecipes()),nil,'TBC Registry flavor cannot seed research forecasts into Forever')
  eq(type(L.CatalogueStatus().providerRejected),'string','unsupported provider metadata explains why it was rejected')
  RecipeRegistryRecipeMetadata.flavor='forever'; RecipeRegistryRecipeMetadata.metadataVersion='forever-1.60.1.99999'
  eq(L.CatalogueRecipes()[1250142].databaseReference,true,'newer same-family metadata remains available as an unverified database forecast')
  eq(L.CatalogueRecipes()[1250142].databaseBuildMismatch,true,'newer recipe metadata explicitly records the source build mismatch')
  eq(L.CatalogueRecipes()[1250142].learned,nil,'newer metadata never establishes learnability or character knowledge')
  RecipeRegistryRecipeMetadata.metadataVersion='forever-1.61.1.70800'
  eq(next(L.CatalogueRecipes()),nil,'a different client version family is not trusted as a Forever reference')
  RecipeRegistryRecipeMetadata.metadataVersion='forever-1.60.1.70862'
  eq(L.CatalogueRecipes()[1250142].databaseReference,true,'even same-build database data requires current client verification')

  reset(); RecipeRegistryRecipeMetadata=nil; L.catalogueCandidates={1}; records[1]={learned=false}
  eventFrame.scripts.OnEvent(eventFrame,'PLAYER_LOGIN')
  eq(reads,0,'login catalogue discovery is asynchronous')
  flush()
  eq(L.CatalogueStatus().validated,1,'catalogue starts automatically at login without opening its page')
  reset(); list={1}; records[1]={learned=false}
  eventFrame.scripts.OnEvent(eventFrame,'TRADE_SKILL_SHOW')
  eventFrame.scripts.OnEvent(eventFrame,'TRADE_SKILL_LIST_UPDATE')
  eventFrame.scripts.OnEvent(eventFrame,'TRADE_SKILL_DETAILS_UPDATE')
  eq(#timers,1,'multiple profession notifications schedule one coalesced catalogue pass')
  flush()
  eq(reads,1,'coalesced events do not repeat recipe queries')
  records[1].learned=true
  eventFrame.scripts.OnEvent(eventFrame,'NEW_RECIPE_LEARNED',1); flush()
  eq(L.CatalogueRecipes()[1].learned,true,'newly learned recipes refresh without a manual slash command')
  reset(); C_Timer=nil; list={1}; records[1]={learned=false}
  eventFrame.scripts.OnEvent(eventFrame,'TRADE_SKILL_SHOW')
  eventFrame.scripts.OnUpdate(eventFrame,0.25)
  eq(reads,0,'timerless client schedules work for a later frame')
  eventFrame.scripts.OnUpdate(eventFrame,0.02)
  eq(L.CatalogueStatus().validated,1,'OnUpdate fallback imports catalogue data when C_Timer is unavailable')
  reset(); C_Timer={After=function(_,callback) timers[#timers+1]=callback end}
  list={1}; records[1]={learned=false}
  eventFrame.scripts.OnEvent(eventFrame,'TRADE_SKILL_SHOW')
  L.db={recipes={}}
  flush()
  eq(reads,0,'deferred event for a previous character database cannot mutate the replacement context')
  for key,wrapped in pairs(globals) do _G[key]=wrapped.value end
end
