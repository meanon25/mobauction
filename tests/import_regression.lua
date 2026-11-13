-- Replay the Cooking/Fishing saved-data failure with independent profession data.
-- Loaded by tests/run.lua after its existing suite; no live account data is used.
return function(F, eq, fire, widget)
  for _, key in ipairs({'window','setup','report','details','settings'}) do
    if F[key] then F[key].suppressReturn=true; F[key]:Hide(); F[key].suppressReturn=nil end
  end
  F.filter=nil; F.worthLearning=false
  TradeSkillFrame=nil; CraftFrame=nil
  ProfessionsFrame=widget(); ProfessionsFrame:Hide()
  GetTradeSkillLine=nil; GetNumTradeSkills=nil; GetCraftDisplaySkillLine=nil; GetNumCrafts=nil
  IsTradeSkillLinked=nil; IsTradeSkillGuild=nil; C_SkillInfo=nil

  local ranks={[185]=244,[164]=190,[356]=1}
  local professionIDs={185,164,356}
  GetProfessions=function() return 1,2,3 end
  GetProfessionInfo=function(index)
    local id=professionIDs[index]
    return F.professions[id],nil,ranks[id],300,nil,nil,id
  end
  local rows={
    [2538]={name='Charred Wolf Meat',profession=185,learned=true,output=2679,reagent=2672},
    [2540]={name='Roasted Boar Meat',profession=185,learned=true,output=2681,reagent=769},
    [2660]={name='Rough Sharpening Stone',profession=164,learned=true,output=2862,reagent=2835},
  }
  local activeProfession, activeIDs, sourceCounter=185,{2538,2540},10
  local missingIdentity, missingSchematic, missingInfo, invalidBase, changeDuringRead
  local function professionInfo(id)
    return {professionID=id,professionName=F.professions[id],skillLevel=ranks[id],sourceCounter=sourceCounter}
  end
  C_TradeSkillUI={
    GetBaseProfessionInfo=function()
      if invalidBase then return {professionID=0,professionName='',skillLevel=0,sourceCounter=sourceCounter} end
      return professionInfo(activeProfession)
    end,
    GetAllRecipeIDs=function() return activeIDs end,
    GetProfessionInfoByRecipeID=function(id)
      if missingIdentity then return nil end
      return rows[id] and professionInfo(rows[id].profession)
    end,
    GetRecipeInfo=function(id) if not missingInfo then return rows[id] end end,
    GetRecipeSchematic=function(id)
      if missingSchematic then return nil end
      if changeDuringRead and id==2540 then sourceCounter=sourceCounter+1 end
      local row=rows[id]
      return {outputItemID=row.output,quantityMin=1,reagentSlotSchematics={
        {reagentType=0,quantityRequired=1,reagents={{itemID=row.reagent}}},
      }}
    end,
  }
  local function savedRecipe(id, profession, observedSkill, reader)
    local row=rows[id]
    return {id=id,name=row.name,profession=profession,learned=true,output=row.output,made=1,
      reagents={{itemID=row.reagent,qty=1}},observedBuild=F.Build(),observedSkill=observedSkill,
      trainerAvailable=true,trainerSeen=time(),trainerName='Previous trainer',trainingCost=123,reader=reader}
  end
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,
    setupComplete=true,selectedProfessions={[185]=true,[164]=true,[356]=true},
    professionNames={[0]='',[185]='Cooking',[164]='Blacksmithing',[356]='Fishing'},
    skills={[185]=225},detectedSkills={[185]=244,[164]=190,[356]=1},
    recipes={[2538]=savedRecipe(2538,356,1),[2660]=savedRecipe(2660,164,190,'legacy')},
  }
  F.professions[0]=''
  F.Init()
  eq(F.professions[0],nil,'empty profession zero removed from saved names')
  eq(F.ProfessionIDByName(''),nil,'empty name cannot resolve to a profession')
  eq(F.db.recipes[2538].observedBuild,nil,'old modern attribution requires a fresh observation')
  eq(F.db.recipes[2538].observedSkill,nil,'old Fishing rank cannot validate a Cooking recipe')
  eq(F.db.recipes[2660].observedBuild,F.Build(),'explicit legacy attribution survives migration')
  F.DiscoverProfessions()

  -- The profession windows are opened first, then used later with only /moba open.
  ProfessionsFrame:Show(); fire('TRADE_SKILL_SHOW')
  eq(F.db.recipes[2538].profession,185,'opening Cooking repairs saved Fishing attribution')
  eq(F.db.recipes[2538].observedSkill,244,'Cooking records Cooking rank rather than Fishing rank')
  eq(F.db.recipes[2540].profession,185,'second Cooking recipe assigned independently')
  eq(F.db.recipes[2538].professionVerified,true,'modern attribution is marked verified')
  eq(F.db.recipes[2538].trainerAvailable,nil,'misattributed trainer evidence discarded')
  eq(F.Eligible(F.db.recipes[2538]),false,'manual Cooking225 does not prove eligibility at observed244')
  F.SetSkill(185,'auto')
  eq(F.Eligible(F.db.recipes[2538]),true,'automatic Cooking rank restores learned recipe eligibility')

  -- Test saveRecipe directly through import, independent of startup migration.
  local wrong=savedRecipe(2538,356,1)
  wrong.professionVerified=true; F.db.recipes[2538]=wrong
  F.ReadRecipes()
  eq(F.db.recipes[2538].observedSkill,244,'repair does not inherit another profession minimum observation')
  eq(F.db.recipes[2538].trainerName,nil,'repair does not inherit another profession trainer name')
  eq(F.db.recipes[2538].trainingCost,nil,'repair does not inherit another profession training cost')
  F.db.recipes[2538].trainerAvailable=true; F.db.recipes[2538].trainerName='Cooking trainer'
  ranks[185]=245; F.ReadRecipes()
  eq(F.db.recipes[2538].observedSkill,244,'same-profession reimport retains earliest proven learned rank')
  eq(F.db.recipes[2538].trainerName,'Cooking trainer','same-profession reimport retains matching trainer evidence')
  F.Init()
  eq(F.db.recipes[2538].observedBuild,F.Build(),'verified current imports survive another initialization')

  -- Skill enumeration can itself change the global source. Capture recipe data
  -- first, and reject the stale Cooking list on the next pass through Fishing.
  local discover=F.DiscoverProfessions
  F.DiscoverProfessions=function()
    local found=discover()
    activeProfession=356
    return found
  end
  ranks[185]=244; F.db.recipes[2538]=nil
  eq(F.ReadRecipes(),2,'recipe snapshot completes before discovery changes the source')
  eq(F.db.recipes[2538].profession,185,'discovery side effect cannot relabel captured Cooking data')
  eq(F.db.recipes[2538].observedSkill,244,'captured Cooking rank survives discovery side effect')
  local captured=F.db.recipes[2538]
  eq(F.ReadRecipes(),0,'next refresh rejects Fishing context with stale Cooking IDs')
  eq(F.db.recipes[2538],captured,'rejected refresh preserves previously captured Cooking data')
  F.DiscoverProfessions=discover

  activeProfession=164; activeIDs={2660}; sourceCounter=sourceCounter+1
  fire('TRADE_SKILL_DATA_SOURCE_CHANGING'); fire('TRADE_SKILL_DATA_SOURCE_CHANGED')
  F.ReadRecipes()
  eq(F.db.recipes[2660].profession,164,'switching to Blacksmithing imports its own recipes')
  eq(F.db.recipes[2660].observedSkill,190,'Blacksmithing records its own rank')
  eq(F.db.recipes[2538].profession,185,'Blacksmithing import leaves Cooking saved')

  -- Reproduce the stale-list race: the base changes to Fishing before IDs change.
  local cooking=F.db.recipes[2538]
  activeProfession=356; activeIDs={2538,2540}; sourceCounter=sourceCounter+1
  rows[2538].learned=false
  eq(F.ReadRecipes(),0,'mismatched Fishing source cannot import Cooking IDs')
  eq(F.db.recipes[2538],cooking,'mismatched source leaves saved Cooking record untouched')
  eq(F.db.recipes[2538].learned,true,'mismatched source cannot unlearn a known Cooking recipe')
  rows[2538].learned=true

  -- Loading errors preserve a complete existing observation.
  activeProfession=185; activeIDs={2538}; sourceCounter=sourceCounter+1
  missingIdentity=true; F.ReadRecipes()
  eq(F.db.recipes[2538],cooking,'loading recipe identity does not fall back to a global guess')
  missingIdentity=false; missingSchematic=true; rows[2538].learned=false
  F.ReadRecipes()
  eq(F.db.recipes[2538],cooking,'loading schematic does not replace a complete saved recipe')
  eq(F.db.recipes[2538].observedBuild,F.Build(),'loading schematic does not erase prior build evidence')
  eq(F.db.recipes[2538].learned,true,'loading schematic does not erase known status')
  missingSchematic=false; missingInfo=true; F.ReadRecipes()
  eq(F.db.recipes[2538],cooking,'loading recipe info leaves saved data intact')
  missingInfo=false; invalidBase=true
  eq(F.ReadRecipes(),0,'empty profession source cannot import cached recipes')
  eq(F.db.recipes[2538],cooking,'invalid base source leaves Cooking intact')
  eq(F.professions[0],nil,'invalid base source cannot recreate profession zero')
  invalidBase=false; rows[2538].learned=true

  -- A source change midway through a list must not partially commit its first row.
  activeIDs={2538,2540}; changeDuringRead=true; rows[2538].learned=false
  local second=F.db.recipes[2540]
  eq(F.ReadRecipes(),0,'mid-import sourceCounter change discards the snapshot')
  eq(F.db.recipes[2538],cooking,'first row is not committed before source stability check')
  eq(F.db.recipes[2540],second,'last row is not committed after source changed')
  changeDuringRead=false; rows[2538].learned=true

  -- A source-changing event also blocks a user Refresh until new data is ready.
  fire('TRADE_SKILL_DATA_SOURCE_CHANGING')
  eq(F.ReadRecipes(),0,'source-changing interval defers manual refresh')
  eq(F.db.recipes[2538],cooking,'source-changing interval preserves imported recipes')
  fire('TRADE_SKILL_DATA_SOURCE_CHANGED')
  F.ReadRecipes()
  eq(F.db.recipes[2538].profession,185,'source-changed event permits a stable Cooking import')

  -- Late details are retried even after the initial show/list event was incomplete.
  F.db.recipes[2540]=nil; missingSchematic=true; fire('TRADE_SKILL_SHOW')
  eq(F.db.recipes[2540],nil,'incomplete initial event does not invent a recipe')
  missingSchematic=false; fire('TRADE_SKILL_DETAILS_UPDATE')
  eq(F.db.recipes[2540] and F.db.recipes[2540].profession,185,'details update imports a now-ready recipe')

  -- Older APIs need an independent visible skill line, never just the global
  -- modern base. A complete legacy reader can still import when modern disagrees.
  local byRecipe=C_TradeSkillUI.GetProfessionInfoByRecipeID
  C_TradeSkillUI.GetProfessionInfoByRecipeID=nil
  TradeSkillFrame=widget()
  GetTradeSkillLine=function() return 'Cooking',244 end
  activeProfession=185
  eq(F.ReadRecipes(),2,'visible legacy Cooking identity validates modern API without recipe ownership')
  eq(F.db.recipes[2538].reader,'modern','validated modern reader supplies complete schematics')
  local compatible=F.db.recipes[2538]
  activeProfession=356
  eq(F.ReadRecipes(),0,'legacy Cooking name rejects modern Fishing source')
  eq(F.db.recipes[2538],compatible,'rejected compatibility import leaves Cooking untouched')
  GetNumTradeSkills=function() return 1 end
  GetTradeSkillInfo=function() return 'Charred Wolf Meat','optimal' end
  GetTradeSkillItemLink=function() return '|Hitem:2679|h[Charred Wolf Meat]|h' end
  GetTradeSkillRecipeLink=function() return '|Henchant:2538|h[Charred Wolf Meat]|h' end
  GetTradeSkillNumMade=function() return 1 end
  GetTradeSkillNumReagents=function() return 1 end
  GetTradeSkillReagentInfo=function() return 'Stringy Wolf Meat',nil,1 end
  GetTradeSkillReagentItemLink=function() return '|Hitem:2672|h[Stringy Wolf Meat]|h' end
  eq(F.ReadRecipes(),1,'complete legacy reader imports despite mismatched modern context')
  eq(F.db.recipes[2538].reader,'legacy','mismatched modern context uses explicit legacy reader')
  eq(F.db.recipes[2538].profession,185,'legacy fallback records Cooking rather than modern Fishing')
  eq(F.db.recipes[2538].observedSkill,244,'legacy fallback retains Cooking rank')
  C_TradeSkillUI.GetProfessionInfoByRecipeID=byRecipe
  TradeSkillFrame=nil; GetTradeSkillLine=nil; GetNumTradeSkills=nil

  -- Closing profession windows must not make a filter, Refresh or AH scan erase imports.
  ProfessionsFrame:Hide(); fire('TRADE_SKILL_CLOSE')
  local closedCooking,closedSmithing=F.db.recipes[2538],F.db.recipes[2660]
  activeProfession=356; activeIDs={2538,2540}; rows[2538].learned=false
  F.filter=185
  eq(F.ReadRecipes(),0,'closed profession window uses saved recipes without reimport')
  F.Refresh()
  eq(F.db.recipes[2538],closedCooking,'Cooking-only MobAuction filter preserves imported recipe')
  eq(#F.Results(),2,'known Cooking recipes remain visible with profession window closed')
  local terms
  Auctionator.API.v1.MultiSearchExact=function(_, list) terms=list end
  F.ahOpen=true; F.ScanCraftPrices()
  eq(F.db.recipes[2538],closedCooking,'AH scan does not relabel Cooking from a stale global source')
  eq(F.db.recipes[2660],closedSmithing,'AH scan retains Blacksmithing imports')
  eq(type(terms),'table','saved Cooking recipes can still request AH prices')
  local searched={}; for _,term in ipairs(terms or {}) do searched[term]=true end
  eq(searched['Item 2679'],true,'closed-window Cooking scan includes learned output')
  eq(searched['Item 2672'],true,'closed-window Cooking scan includes its reagent')

  -- Automatic-level actions must show the cause of exclusions and avoid
  -- silently changing unrelated or currently undetected profession overrides.
  F.db.selectedProfessions={[185]=true,[171]=true}
  F.db.skills={[185]=225,[164]=170,[171]=120}
  F.db.detectedSkills[171]=150
  local skillStatus=F.SkillStatus(185)
  eq(skillStatus:find('225',1,true)~=nil and skillStatus:find('244',1,true)~=nil,true,'skill status exposes manual225 and detected244')
  local changed,available=F.UseDetectedLevels()
  eq(changed,1,'automatic levels clears only a selected currently detected override')
  eq(available,1,'stale detected cache does not count as current detection')
  eq(F.db.skills[185],nil,'selected Cooking follows detected skill after action')
  eq(F.db.skills[164],170,'unselected Blacksmithing preview is preserved')
  eq(F.db.skills[171],120,'undetected selected Alchemy preview is preserved')
  F.SetSkill(185,'225'); F.activeTab='crafting'; F.Open()
  F.useDetectedButton.scripts.OnClick()
  eq(F.db.skills[185],nil,'main Use detected levels button clears selected override')
  eq(F.skillLabel.text:find('detected 244',1,true)~=nil,true,'main button refreshes displayed detected rank')
  eq(#F.results,2,'main button restores Cooking results without reopening profession')

  F.SetSkill(185,'225'); F.ShowSetup()
  F.setupRows[164].input:SetText('180')
  F.setupRows[171].input:SetText('110')
  F.setupUseDetected.scripts.OnClick()
  eq(F.db.skills[185],nil,'setup Use detected levels clears selected detected override')
  eq(F.setupRows[185].input:GetText(),'244','setup action fills detected Cooking rank')
  eq(F.setupRows[164].input:GetText(),'180','setup action preserves an unselected edited rank')
  eq(F.setupRows[171].input:GetText(),'110','setup action preserves an undetected selected edited rank')
  eq(F.db.skills[164],170,'setup action does not save unrelated edited rank')
  eq(F.db.skills[171],120,'setup action does not replace undetected override with cached rank')
end
