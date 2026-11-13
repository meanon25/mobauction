-- Exact recipe-item mapping and independent, one-craft profit forecasts.
return function(F,eq,fire,widget)
  local savedGlobals={}
  local globals={'C_AuctionHouse','C_TradeSkillUI','C_Item','C_TooltipInfo','Auctionator','AHledgerAPI',
    'AuctionHouseFrame','AuctionFrame','GetProfessions','GetProfessionInfo','hooksecurefunc','time','ITEM_SPELL_KNOWN','C_Timer'}
  for _,key in ipairs(globals) do savedGlobals[key]={value=_G[key]} end
  local savedFields={}
  local fields={'db','window','details','filter','currentProfessions','currentProfessionsComplete','depth','depthRequests',
    'priceCache','depositQuotes','auctionRecipes','ahOpen','Say','GetFullScanSnapshot','FullScanPrice','fullScanRecipes','CatalogueRecipes','CatalogueRecipeIDsForItem','CatalogueRecipeHintsForItem'}
  for _,key in ipairs(fields) do savedFields[key]={value=F[key]} end
  local oldDB=MobAuctionDB
  local now=2000000
  time=function() return now end
  F.window=nil; F.details=nil; F.filter=nil; F.Say=function() end
  AuctionHouseFrame=widget(); AuctionHouseFrame:Show(); AuctionFrame=nil
  GetProfessions=function() return 1 end
  GetProfessionInfo=function() return 'Blacksmithing',nil,190,300,nil,nil,164 end
  local browse,queries,more={}, {},0
  local ready,full=true,false
  local prices={[100]=1000,[101]=1100}
  local spells={[900]=2660,[901]=99999,[902]=2661,[903]=2660}
  local usable,known,owner,missingSlots,wrongRecipeID,tooltipKnown=true,false,164,false,false,false
  local linked,guild,npc,missingInfo,missingOwner=false,false,false,false,false
  local changeSchematic,changeInfo
  local demand,demandSeen,demandSnapshot=3,now,false
  local tooltipSpell,secondTooltipSpell
  local lineTypes=Enum.TooltipDataLineType
  local recipeTypes,slotTypes=Enum.TradeskillRecipeType,Enum.TradeskillSlotDataType
  Enum.TooltipDataLineType={LearnableSpell=6,ItemSpellTriggerLearn=38}
  Enum.TradeskillRecipeType={Item=1,Enchant=2,Salvage=3}
  Enum.TradeskillSlotDataType={Reagent=1,Currency=2}
  ITEM_SPELL_KNOWN='Already known'
  C_Item={
    GetItemInfo=function(id)
      return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,5,id>=900 and 9 or 7,id>=900 and 4 or 0,0
    end,
    GetItemSpell=function(id) return 'Item use spell',spells[id] end,
    IsUsableItem=function() return usable,false end,
    RequestLoadItemDataByID=function() end,
  }
  C_TooltipInfo={GetItemByID=function()
    local lines={}
    if tooltipSpell then lines[#lines+1]={type=6,spellID=tooltipSpell} end
    if secondTooltipSpell then lines[#lines+1]={type=38,spellID=secondTooltipSpell} end
    if tooltipKnown then lines[#lines+1]={leftText=ITEM_SPELL_KNOWN} end
    return {lines=lines}
  end}
  C_TradeSkillUI={
    IsTradeSkillLinked=function() return linked end,
    IsTradeSkillGuild=function() return guild end,
    IsNPCCrafting=function() return npc end,
    GetRecipeInfo=function(id)
      if missingInfo or (id~=2660 and id~=2661) then return nil end
      local info={recipeID=wrongRecipeID and 12345 or id,name='Plan '..id,learned=known}
      if changeInfo then changeInfo(info) end
      return info
    end,
    GetProfessionInfoByRecipeID=function() if not missingOwner then return {professionID=owner,professionName=F.professions[owner]} end end,
    GetRecipeSchematic=function(id)
      local schematic={recipeID=id,outputItemID=id==2661 and 101 or 100,quantityMin=1,reagentSlotSchematics=not missingSlots and {
        {reagentType=0,quantityRequired=2,reagents={{itemID=200}}},
      } or nil}
      if changeSchematic then changeSchematic(schematic) end
      return schematic
    end,
  }
  C_AuctionHouse={
    IsThrottledMessageSystemReady=function() return ready end,
    SendBrowseQuery=function(query) queries[#queries+1]=query end,
    GetBrowseResults=function() return browse end,
    HasFullBrowseResults=function() return full end,
    RequestMoreBrowseResults=function() more=more+1 end,
    MakeItemKey=function(id) return {itemID=id} end,
    GetItemKeyInfo=function() return {isCommodity=true} end,
    CalculateCommodityDeposit=function(_,_,quantity) return 10*quantity end,
  }
  hooksecurefunc=function(tbl,key,callback)
    local original=tbl[key]
    tbl[key]=function(...) local result={original(...)}; callback(...); return unpack(result) end
  end
  Auctionator={API={v1={
    GetAuctionPriceByItemID=function(_,id) return prices[id] end,
    GetAuctionAgeByItemID=function() return 0 end,
  }}}
  AHledgerAPI={GetPrice=function(id)
    if id==100 or id==101 then return {soldPerDay=demand,updated=demandSeen,snapshot=demandSnapshot} end
  end}
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[164]=true}}
  F.Init(); F.DiscoverProfessions(); F.SetAuctionHouseOpen(true)
  if not F.AuctionLearningRows then assert(loadfile('MobAuction/AuctionLearning.lua'))('MobAuction',F) end
  local function depth()
    F.depth={[200]={kind='commodity',complete=true,seen=now,lots={{price=100,quantity=100}}}}
    F.depositQuotes={}; F.priceCache={}
  end
  local function observe(id,price,own,account)
    browse={{itemKey={itemID=id or 900},minPrice=price or 50000,containsOwnerItem=own,containsAccountItem=account}}
    F.ObserveAuctionRecipes()
  end
  local function reset()
    F.ClearAuctionLearning(); F.db.recipes={}; F.db.skills={}; F.db.requirements={}; F.db.verifiedRequirements={}
    F.db.selectedProfessions={[164]=true}; F.db.strictCosts=true; F.db.vendors={}; F.db.deposits={}
    F.db.cut=5; F.db.duration=1; F.db.failures=1; F.db.maxAge=1
    usable=true; known=false; owner=164; missingSlots=false; wrongRecipeID=false; tooltipKnown=false
    linked=false; guild=false; npc=false; missingInfo=false; missingOwner=false; changeSchematic=nil; changeInfo=nil
    tooltipSpell=nil; secondTooltipSpell=nil; demand=3; demandSeen=now; demandSnapshot=false
    F.currentProfessions={[164]=190}; F.currentProfessionsComplete=true; F.db.detectedSkills[164]=190
    depth(); observe()
  end
  reset()
  local row=F.EvaluateAuctionLearning(900)
  eq(row.recipe.id,2660,'exact item spell maps to a validated crafting recipe')
  eq(row.recipe.profession,164,'recipe mapping uses its independent profession identity')
  eq(F.db.recipes[2660].professionVerified,true,'explicit validated AH schematic can enter the catalogue')
  eq(row.adjusted,740,'one-craft profit deducts 200 materials, 50 cut and 10 failed deposit')
  eq(row.acquisitionPrice,50000,'recipe purchase price is displayed separately')
  eq(row.acquisitionChecked,false,'browse minimum is explicitly an estimate')
  eq(row.training,nil,'auction row does not disguise recipe price as training cost')
  eq(row.afterTraining,nil,'auction row has no acquisition-deducted profit')
  eq(row.candidate,true,'verified usable positive craft with recent estimated demand is flagged')
  observe(900,9999999)
  local expensive=F.EvaluateAuctionLearning(900)
  eq(expensive.adjusted,row.adjusted,'changing recipe price cannot change crafting profit')
  eq(expensive.candidate,true,'expensive recipe does not suppress a craft-profit flag')
  F.depth[900]={kind='item',complete=true,seen=now,lots={{price=65000,quantity=2}}}
  row=F.EvaluateAuctionLearning(900)
  eq(row.acquisitionPrice,65000,'checked recipe purchase displays full indivisible stack cost')
  eq(row.acquisitionChecked,true,'full fresh recipe depth is labeled checked')
  eq(row.adjusted,740,'checked acquisition cost remains excluded from profit')
  prices[100]=2000
  eq(F.EvaluateAuctionLearning(900).adjusted,1690,'direct detail evaluation clears an old scalar output-price cache')
  prices[100]=1000

  -- Required quantities must be purchasable; estimate mode cannot bypass this.
  F.depth[200].lots={{price=1,quantity=1}}; F.db.strictCosts=false
  row=F.EvaluateAuctionLearning(900)
  eq(row.adjusted,nil,'one cheap reagent cannot price a craft requiring two')
  eq(row.candidate,false,'incomplete ingredient quantity cannot receive a learning flag')
  eq(row.flag,'needs_check','mapped missing-price candidate stays visible with its reason')
  eq(#F.AuctionLearningRows(),1,'pending mapped recipe is not silently hidden')
  reset(); F.depth[200].complete=false
  eq(F.EvaluateAuctionLearning(900).candidate,false,'partial depth is not checked ingredient supply')
  reset(); F.depth[200].seen=now-61
  eq(F.EvaluateAuctionLearning(900).candidate,false,'old depth cannot qualify as current supply')
  reset(); F.depth[200]=nil
  F.db.vendors[200]={price=100,bundle=5,seen=now,name='Test supplier'}
  row=F.EvaluateAuctionLearning(900)
  eq(row.cost,100,'supplier reagent cost buys complete vendor bundles')
  eq(row.adjusted,840,'vendor bundles and normal AH fees produce ordinary craft profit')
  eq(row.candidate,true,'recent unlimited supplier observations can supply the craft')
  reset()
  local deposit=F.Deposit
  F.Deposit=function() return nil,'Keep an output in your bags for a quote' end
  row=F.EvaluateAuctionLearning(900)
  eq(row.adjusted,nil,'unknown deposit never becomes a free listing')
  eq(row.candidate,false,'unknown deposit prevents a strong learning flag')
  F.Deposit=deposit

  reset(); demand=nil
  row=F.EvaluateAuctionLearning(900)
  eq(row.profitCandidate,true,'checked profitable craft remains a candidate with unknown demand')
  eq(row.candidate,false,'unknown demand cannot support the stronger flag')
  eq(row.status,'Profitable craft; demand unknown','unknown demand is explicit')
  demand=3; demandSeen=now-86401
  eq(F.EvaluateAuctionLearning(900).demandPerDay,nil,'stale historical demand is excluded')
  demandSeen=now; demandSnapshot=true
  eq(F.EvaluateAuctionLearning(900).demandPerDay,nil,'downloaded snapshot demand cannot look like a fresh observation')
  demandSnapshot=false; demand=0.2
  eq(F.EvaluateAuctionLearning(900).candidate,false,'low estimated demand does not earn the strong flag')

  reset(); usable=false; F.db.skills[164]=300
  row=F.EvaluateAuctionLearning(900)
  eq(row.canLearn,false,'manual high skill cannot override the game rejecting the item')
  eq(row.profitCandidate,false,'unlearnable item is not a profitable learning recommendation')
  eq(row.adjusted,740,'learning eligibility does not conceal the underlying craft forecast')
  usable=nil
  eq(F.EvaluateAuctionLearning(900).canLearn,false,'missing usable evidence stays unverified')
  reset(); F.currentProfessionsComplete=false
  eq(F.EvaluateAuctionLearning(900).canLearn,false,'cached skill alone does not prove current profession ownership')
  reset(); F.db.skills[164]=180
  eq(F.EvaluateAuctionLearning(900).canLearn,false,'unknown minimum is not assumed below observed current skill')
  F.db.requirements[2660]={rank=175,build=F.Build()}
  eq(F.EvaluateAuctionLearning(900).canLearn,true,'verified lower minimum can support a lower preview with usable game evidence')
  F.db.requirements[2660]={rank=200,build=F.Build()}; F.db.skills[164]=300
  eq(F.EvaluateAuctionLearning(900),nil,'known minimum above actual skill excludes the recipe despite a manual high preview')

  reset(); observe(901)
  local unknown=F.EvaluateAuctionLearning(901)
  eq(unknown,nil,'an item-use wrapper without a matching recipe is never guessed into a recipe')
  eq(F.db.recipes[99999],nil,'wrapper ID cannot fabricate a catalogue row')
  tooltipSpell=2660
  eq(F.EvaluateAuctionLearning(901).recipe.id,2660,'optional learnable-tooltip ID works only after full recipe validation')
  secondTooltipSpell=2661
  eq(F.EvaluateAuctionLearning(901),nil,'two different validated learn IDs remain ambiguous')
  reset(); wrongRecipeID=true
  eq(F.EvaluateAuctionLearning(900),nil,'API response recipeID must equal the requested spell candidate')
  reset(); owner=185
  eq(F.EvaluateAuctionLearning(900),nil,'Blacksmithing plan subclass cannot be attributed to Cooking')
  reset(); missingSlots=true
  eq(F.EvaluateAuctionLearning(900),nil,'incomplete schematic is not inserted as a verified AH recipe')
  eq(F.db.recipes[2660],nil,'missing schematic cannot create a half-verified unlearned recipe')
  reset(); changeSchematic=function(s) s.recipeID=2661 end
  eq(F.EvaluateAuctionLearning(900),nil,'schematic for a different recipe cannot supply an item teaching candidate')
  eq(F.db.recipes[2660],nil,'mismatched schematic cannot be persisted as the requested recipe')
  reset(); changeSchematic=function(s) s.recipeID=nil end
  eq(F.EvaluateAuctionLearning(900),nil,'schematic without its own identity is not treated as exact recipe evidence')
  for _,flag in ipairs({'isRecraft','isSalvageRecipe','isDummyRecipe','isGatheringRecipe'}) do
    reset(); changeInfo=function(info) info[flag]=true end
    eq(F.EvaluateAuctionLearning(900),nil,'unsupported recipe-info flag '..flag..' cannot create a crafting candidate')
    reset(); changeSchematic=function(s) s[flag]=true end
    eq(F.EvaluateAuctionLearning(900),nil,'unsupported schematic flag '..flag..' cannot create a crafting candidate')
  end
  reset(); changeSchematic=function(s) s.recipeType=Enum.TradeskillRecipeType.Enchant end
  eq(F.EvaluateAuctionLearning(900),nil,'non-item schematic is excluded even if an output item ID is supplied')
  reset(); changeSchematic=function(s) s.quantityMin=0.5 end
  eq(F.EvaluateAuctionLearning(900),nil,'fractional output cannot price a craftable item batch')
  reset(); changeSchematic=function(s) s.reagentSlotSchematics[1].reagents[1].currencyID=1 end
  eq(F.EvaluateAuctionLearning(900),nil,'currency requirement cannot be priced as an ordinary auction reagent')
  reset(); changeSchematic=function(s) s.reagentSlotSchematics[1].quantityRequired=0.5 end
  eq(F.EvaluateAuctionLearning(900),nil,'fractional reagent requirement cannot be treated as an ordinary recipe')
  reset(); changeSchematic=function(s) s.reagentSlotSchematics[1].variableQuantities={1,2} end
  eq(F.EvaluateAuctionLearning(900),nil,'variable ingredient requirement remains unsupported')
  reset(); changeSchematic=function(s) s.reagentSlotSchematics[1].dataSlotType=Enum.TradeskillSlotDataType.Currency end
  eq(F.EvaluateAuctionLearning(900),nil,'non-reagent slot type cannot be interpreted as materials')
  reset(); changeSchematic=function(s) s.reagentSlotSchematics[1].reagents[1]=false end
  eq(F.EvaluateAuctionLearning(900),nil,'malformed ingredient option is rejected without a Lua error')
  for _,source in ipairs({'linked','guild','npc'}) do
    reset(); changeSchematic=function()
      linked=source=='linked'; guild=source=='guild'; npc=source=='npc'
    end
    eq(F.EvaluateAuctionLearning(900),nil,'source changing to '..source..' during schematic read invalidates the candidate')
    eq(F.db.recipes[2660],nil,'source changing to '..source..' cannot persist foreign recipe knowledge')
  end
  reset(); known=true
  eq(F.EvaluateAuctionLearning(900),nil,'currently learned recipes are removed from purchase candidates')
  reset(); tooltipKnown=true
  eq(F.EvaluateAuctionLearning(900),nil,'explicit already-known item text vetoes the offer')
  reset(); F.db.recipes[2660]={id=2660,learned=true,observedBuild=F.Build()}
  eq(F.EvaluateAuctionLearning(900).recipe.learned,false,'current exact own-character API knowledge supersedes earlier saved known status')
  reset(); F.db.recipes[2660]={id=2660,learned=true,observedBuild=F.Build()}; missingInfo=true
  eq(F.EvaluateAuctionLearning(900),nil,'saved known status is retained while no newer character knowledge is available')
  reset(); linked=true
  eq(F.EvaluateAuctionLearning(900),nil,'linked profession context cannot establish current-character learned status')
  eq(F.db.recipes[2660],nil,'linked context cannot create an unlearned catalogue entry')
  reset(); F.EvaluateAuctionLearning(900); missingInfo=true; missingOwner=true
  eq(F.EvaluateAuctionLearning(900).recipe.id,2660,'a complete verified current-build import remains usable while its profession API is inactive')
  missingOwner=false; owner=185
  eq(F.EvaluateAuctionLearning(900),nil,'live conflicting profession identity vetoes a cached import')
  owner=164; missingInfo=false; known=true
  eq(F.EvaluateAuctionLearning(900),nil,'live learned status vetoes cached unlearned data')
  known=false; missingInfo=true; F.db.recipes[2660].professionVerified=false
  eq(F.EvaluateAuctionLearning(900),nil,'unverified older imports cannot supply inactive API fallback')

  reset(); observe(900,1,true,false)
  eq(F.EvaluateAuctionLearning(900),nil,'own browse minimum is not a purchasable recipe offer')
  observe(900,1,false,true)
  eq(F.EvaluateAuctionLearning(900),nil,'account-owned browse minimum is excluded')
  reset(); now=now+301
  eq(F.EvaluateAuctionLearning(900),nil,'recipe browse observations expire after five minutes')
  fire('GET_ITEM_INFO_RECEIVED',900,true)
  eq(F.EvaluateAuctionLearning(900),nil,'item cache traffic cannot refresh the timestamp of an old listing')
  reset(); observe(902,1)
  local ranked=F.AuctionLearningRows()
  eq(ranked[1].recipe.id,2661,'recipe offers sort by craft profit')
  observe(902,99999999); ranked=F.AuctionLearningRows()
  eq(ranked[1].recipe.id,2661,'recipe acquisition price cannot change profit ordering')

  reset(); F.depth[200]=nil; prices[200]=20
  local forecast=F.EvaluateAuctionLearning(900)
  eq(forecast.profit,910,'learning can show a recent ingredient forecast before quantity checks')
  eq(forecast.estimated,true,'forecast ingredient stock is explicitly unverified')
  eq(forecast.candidate,false,'forecast costs cannot earn a checked learning flag')
  F.db.assumedDeposit=100
  eq(F.Deposit(100,1,1),100,'one silver deposit assumption is available without an owned output')
  eq(F.Deposit(100,3,1),300,'deposit assumption scales per output item')
  eq(F.EvaluateAuctionLearning(900).adjusted,810,'learning applies the assumed failed deposit to craft profit')
  F.db.assumedDeposit=false; prices[200]=nil
  reset(); observe(901,1234)
  local pendingRows=F.AuctionLearningRows()
  local foundPending=false
  for _,r in ipairs(pendingRows) do if r.acquisitionItemID==901 then
    foundPending=true; eq(r.profit,nil,'unmapped recipe listing never receives invented crafting profit')
    eq(r.acquisitionPrice,1234,'unmapped recipe listing still shows its auction price')
  end end
  eq(foundPending,true,'recipe listings with unavailable craft data remain visible for investigation')
  -- Complete full scans feed recipe offers directly; unrelated browses and AH
  -- closure cannot erase their still-valid, explicitly estimated observations.
  reset(); F.auctionRecipes={}
  local snapshot={complete=true,seen=now,items={
    [900]={minUnit=12000,minBuyout=24000,name='Snapshot plan',class=9,subclass=4,ownerUnknown=true},
    [200]={minUnit=100,minBuyout=100,class=7,subclass=0},
    [100]={minUnit=1000,minBuyout=1000,class=7,subclass=0},
  }}
  F.GetFullScanSnapshot=function() return snapshot end
  F.FullScanPrice=function(id)
    local item=snapshot and snapshot.items[id]
    return item and item.minUnit,'Full AH scan','Snapshot availability unverified'
  end
  eq(F.ObserveFullScanRecipes({complete=false,items={}}),false,'partial full scan cannot replace recipe offers')
  eq(F.ObserveFullScanRecipes(snapshot),true,'complete full scan can supply recipe offers')
  row=F.EvaluateAuctionLearning(900)
  eq(row.acquisitionPrice,24000,'snapshot recipe price is full minimum buyout rather than fractional unit cost')
  eq(row.acquisitionChecked,false,'snapshot recipe offer is not a checked purchase quote')
  eq(row.fromFullScan,true,'snapshot provenance stays on the recipe candidate')
  observe(200,100)
  eq(F.EvaluateAuctionLearning(900).acquisitionPrice,24000,'browsing ingredients does not erase snapshot recipe offers')
  observe(900,1000,true,false)
  eq(F.EvaluateAuctionLearning(900),nil,'a newer own-only browse result supersedes an older snapshot offer')
  F.ObserveFullScanRecipes(snapshot); F.auctionRecipes={}; F.db.assumedDeposit=100; prices[200]=100
  AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED')
  row=F.EvaluateAuctionLearning(900)
  eq(row.acquisitionPrice,24000,'fresh completed snapshot remains inspectable after closing the AH')
  eq(row.adjusted,650,'offline snapshot candidate uses forecast materials and assumed deposit')
  eq(row.estimated,true,'offline snapshot costs are forecast evidence')
  eq(#F.AuctionLearningRows(),1,'offline snapshot rows survive lifecycle checks during ingredient quoting')
  snapshot=nil
  eq(F.EvaluateAuctionLearning(900),nil,'expired or wrong-market snapshot cannot leave a usable recipe offer')
  F.GetFullScanSnapshot=nil; F.FullScanPrice=savedFields.FullScanPrice.value; prices[200]=nil; F.db.assumedDeposit=false
  AuctionHouseFrame:Show(); F.SetAuctionHouseOpen(true)

  -- Reference catalogue recipes are research, never character-known imports.
  reset(); missingInfo=true; missingOwner=true; F.db.recipes={}
  local reference={id=2660,name='Reference plan',profession=164,output=100,made=1,
    reagents={{itemID=200,qty=2}},observedBuild=F.Build(),referenceOnly=true}
  F.CatalogueRecipes=function() return {[2660]=reference} end
  F.CatalogueRecipeIDsForItem=function(id) return id==901 and {2660} or {} end
  observe(901,9999)
  row=F.EvaluateAuctionLearning(901)
  eq(row.recipe.id,2660,'validated catalogue teaching map resolves an otherwise opaque use-spell wrapper')
  eq(row.adjusted,740,'catalogue recipe can be priced without an active profession API')
  eq(row.canLearn,false,'unknown character learning status cannot be promoted to confirmed unlearned')
  eq(F.db.recipes[2660],nil,'reference recipe stays out of character learned imports')
  F.db.recipes[2660]={id=2660,profession=164,output=100,learned=true,observedBuild=F.Build(),observedAt=now-10}
  reference.learned=false; reference.knowledgeVerified=true; reference.observedAt=now
  eq(F.EvaluateAuctionLearning(901).recipe.learned,false,'newer verified reference knowledge overrides an older known import at the AH')
  eq(F.EvaluateCatalogueLearning(2660).recipe.learned,false,'catalogue research does not merge stale known status over newer verified knowledge')
  reference.output=101
  eq(F.EvaluateAuctionLearning(901).recipe.output,101,'newer verified reference preserves corrected output over older imported facts')
  reference.output=100; reference.observedAt=now-20
  eq(F.EvaluateAuctionLearning(901),nil,'older reference knowledge cannot overturn a newer known import')
  eq(F.EvaluateCatalogueLearning(2660),nil,'older unlearned reference remains suppressed by newer character known status')
  reference.observedAt=now; reference.knowledgeVerified=nil
  eq(F.EvaluateAuctionLearning(901),nil,'unverified reference knowledge cannot overturn known character status')
  reference.learned=nil; reference.observedAt=nil; F.db.recipes[2660]=nil
  F.db.recipes[2660]={id=2660,profession=164,problem='Old incomplete import'}
  eq(F.EvaluateAuctionLearning(901).recipe.id,2660,'incomplete saved imports cannot hide a valid current-build reference recipe')
  F.db.recipes[2660]=nil
  local research=F.CatalogueLearningRows()
  eq(#research,1,'unlisted reference recipe appears in broader learning research')
  eq(research[1].acquisition,'catalogue','unlisted research does not claim an auction purchase source')
  eq(research[1].acquisitionPrice,nil,'unlisted reference recipe has no fabricated purchase price')
  eq(#F.CatalogueLearningRows({[2660]=true}),0,'already listed or trainer recipes can be deduplicated from research')
  reference.learned=true
  eq(#F.CatalogueLearningRows(),0,'known reference recipes are excluded from learning research')
  reference.learned=false; F.db.requirements[2660]={rank=200,build=F.Build()}
  eq(#F.CatalogueLearningRows(),0,'above-skill reference recipes are excluded from learning research')
  F.db.requirements={}; reference.learned=nil; reference.observedBuild=nil
  reference.databaseReference=true; reference.databaseSource='Recipe Registry Forever'; reference.databaseRequiredSkill=175
  row=F.EvaluateCatalogueLearning(2660)
  eq(row.adjusted,740,'external Forever reference can show separately identified craft forecasts')
  eq(row.estimated,true,'database crafting data remains forecast evidence even with checked materials')
  eq(row.canLearn,false,'database data cannot establish character learnability')
  eq(row.candidate,false,'database-only research cannot earn a confirmed recommendation')
  eq(row.databaseReference,true,'database provenance remains visible to the UI')
  reference.databaseRequiredSkill=200
  eq(#F.CatalogueLearningRows(),0,'database minimum above actual skill conservatively excludes the research row')
  reference.databaseRequiredSkill=nil
  eq(#F.CatalogueLearningRows(),1,'unknown database minimum remains visible with pending confirmation')
  local catalogueReads=0
  F.CatalogueRecipes=function() catalogueReads=catalogueReads+1; return {[2660]=reference} end
  F.CatalogueLearningRows()
  eq(catalogueReads,1,'catalogue research builds the reference map only once per pass')
  catalogueReads=0; F.AuctionLearningRows()
  eq(catalogueReads,1,'auction research builds the reference map only once per pass')
  -- A database item association stays unverified even when the craft itself
  -- has a live schematic. Only an actual item effect confirms that mapping.
  missingInfo=false; missingOwner=false
  F.CatalogueRecipeIDsForItem=function() return {} end
  F.CatalogueRecipeHintsForItem=function(id) return id==901 and {2660} or {} end
  row=F.EvaluateAuctionLearning(901)
  eq(row.databaseMapping,true,'database recipe-item association is retained as a reference hint')
  eq(row.canLearn,false,'live craft data cannot promote a database-only teaching association')
  eq(row.candidate,false,'unverified teaching association cannot receive a strong learning flag')
  eq(F.db.recipes[2660],nil,'database-only association cannot create a character recipe import')
  tooltipSpell=2660
  row=F.EvaluateAuctionLearning(901)
  eq(row.canLearn,true,'current typed learning effect can independently confirm a database association')
  F.CatalogueRecipes=nil; F.CatalogueRecipeIDsForItem=nil; F.CatalogueRecipeHintsForItem=nil
  reset(); ready=false
  eq(F.ScanAuctionRecipes(),false,'browse scan respects auction throttling')
  eq(#queries,0,'throttled scan sends no query')
  ready=true
  eq(F.ScanAuctionRecipes(),true,'explicit Scan recipes starts a browse query')
  eq(queries[1].itemClassFilters[1].classID,9,'recipe scan queries only recipe item class')
  eq(F.MoreAuctionRecipes(),false,'next page waits for current results')
  browse={{itemKey={itemID=900},minPrice=1234}}; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  eq(F.MoreAuctionRecipes(),true,'owned completed page can request more recipe results')
  eq(more,1,'one explicit next-page request is sent')
  fire('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
  C_AuctionHouse.SendBrowseQuery({searchString='Copper Ore',sorts={},filters={}})
  eq(F.MoreAuctionRecipes(),false,'another addon browse query revokes page ownership')
  eq(more,1,'foreign browse query is never paginated by this addon')
  F.ScanAuctionRecipes(); full=true; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  eq(F.MoreAuctionRecipes(),false,'complete browse result does not request another page')
  -- One explicit scan continues pages automatically, waits through throttling,
  -- and cannot paginate another addon's search.
  local timers={}
  C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
  local function tick() local fn=table.remove(timers,1); if fn then fn() end end
  full=false; ready=true; F.ScanAuctionRecipes()
  browse={{itemKey={itemID=900},minPrice=1000}}; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  local beforeMore=more
  ready=false; tick(); eq(more,beforeMore,'automatic paging waits when auction requests are throttled')
  ready=true; tick(); eq(more,beforeMore+1,'automatic recipe scan requests the next available page')
  browse={{itemKey={itemID=902},minPrice=2000}}; full=true; fire('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
  tick(); eq(more,beforeMore+1,'automatic paging stops when all recipe pages arrive')
  eq(F.auctionRecipes[900]~=nil and F.auctionRecipes[902]~=nil,true,'all returned recipe pages contribute listings')
  full=false; F.ScanAuctionRecipes(); fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  C_AuctionHouse.SendBrowseQuery({searchString='Other addon search',sorts={}})
  beforeMore=more; tick(); eq(more,beforeMore,'queued automatic paging stops after another browse query')
  timers={}; F.ScanAuctionRecipes(); now=now+121; tick()
  eq(F.AuctionLearningStatus():find('Scan paused',1,true)~=nil,true,'stalled recipe scan reports incomplete coverage instead of claiming completion')
  C_Timer=nil
  AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED')
  eq(next(F.auctionRecipes),nil,'closing the auction house clears learning offers')
  eq(F.ScanAuctionRecipes(),false,'closed auction house blocks recipe scans')

  F.ClearAuctionLearning()
  Enum.TooltipDataLineType=lineTypes
  Enum.TradeskillRecipeType=recipeTypes; Enum.TradeskillSlotDataType=slotTypes
  for key,record in pairs(savedGlobals) do _G[key]=record.value end
  for key,record in pairs(savedFields) do F[key]=record.value end
  MobAuctionDB=oldDB
end
