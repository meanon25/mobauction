-- Forever's selected child line, asynchronous readiness, and saved diagnostics.
return function(F, eq, fire, widget)
  for _,key in ipairs({'window','setup','report','details','settings'}) do
    if F[key] then F[key].suppressReturn=true; F[key]:Hide(); F[key].suppressReturn=nil end
  end
  TradeSkillFrame=nil; CraftFrame=nil
  ProfessionsFrame=widget(); ProfessionsFrame:Show()
  GetTradeSkillLine=nil; GetNumTradeSkills=nil; GetCraftDisplaySkillLine=nil; GetNumCrafts=nil
  IsTradeSkillLinked=nil; IsTradeSkillGuild=nil; C_SkillInfo=nil
  local ranks={[164]=190,[185]=244,[356]=1}
  local professions={164,185,356}
  GetProfessions=function() return 1,2,3 end
  GetProfessionInfo=function(index)
    local id=professions[index]
    return F.professions[id],nil,ranks[id],300,nil,nil,id
  end
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[164]=true,[185]=true}}
  F.Init(); F.filter=164; F.worthLearning=false
  F.recipeSourceOpen=true; F.recipeSourceChanging=false
  local rows={
    [2660]={name='Rough Sharpening Stone',learned=true,output=2862,reagent=2835},
    [2661]={name='Copper Chain Belt',learned=true,output=2851,reagent=2840},
  }
  local ready,changing=true,false
  local childID,childParent,baseID,sourceCounter=164,nil,356,31
  local ids={2660,2661}
  local missingOwner,missingInfo,missingSchematic,missingReagents,foreignOwner,currencyReagent
  local changeCounter,changeChild=false,false
  local function info(id,parent)
    return {professionID=id,parentProfessionID=parent,professionName=F.professions[parent or id],
      parentProfessionName=parent and F.professions[parent],skillLevel=ranks[parent or id],sourceCounter=sourceCounter}
  end
  C_TradeSkillUI={
    IsDataSourceChanging=function() return changing end,
    IsTradeSkillReady=function() return ready end,
    GetBaseProfessionInfo=function() return info(baseID) end,
    GetChildProfessionInfo=function() return childID==0 and {professionID=0} or info(childID,childParent) end,
    GetAllRecipeIDs=function() return ids end,
    GetProfessionInfoByRecipeID=function(id)
      if missingOwner=='all' or missingOwner==id then return nil end
      return info(foreignOwner==id and 185 or 164)
    end,
    GetRecipeInfo=function(id) if missingInfo~=id then return rows[id] end end,
    GetRecipeSchematic=function(id)
      if missingSchematic==id then return nil end
      if changeCounter and id==2661 then sourceCounter=sourceCounter+1 end
      if changeChild and id==2661 then childID=3002 end
      local row=rows[id]
      if currencyReagent==id then return {outputItemID=row.output,quantityMin=1,reagentSlotSchematics={
        {reagentType=0,quantityRequired=1,reagents={{currencyID=2000}}},
      }} end
      return {outputItemID=row.output,quantityMin=1,reagentSlotSchematics=missingReagents==id and {} or {
        {reagentType=0,quantityRequired=1,reagents={{itemID=row.reagent}}},
      }}
    end,
  }

  eq(F.ReadRecipes(),2,'Forever selected child imports while base still describes Fishing')
  eq(F.db.recipes[2660].profession,164,'selected child assigns Blacksmithing identity')
  eq(F.db.recipes[2660].observedSkill,190,'selected child records Blacksmithing rank190')
  local attempt=F.db.lastImportAttempt
  eq(attempt.version,F.VERSION,'latest attempt saves the executing addon version')
  eq(attempt.build,F.Build(),'latest attempt saves the client build')
  eq(attempt.time,time(),'latest attempt saves its observation time')
  eq(attempt.baseID,356,'diagnostics retain conflicting base identity')
  eq(attempt.professionID,164,'diagnostics identify the selected profession')
  eq(attempt.source,'child','diagnostics identify child-first source')
  eq(attempt.idCount,2,'diagnostics record list size')
  eq(attempt.count,2,'diagnostics record committed count')
  eq(attempt.why,'Imported 2 Blacksmithing plans.','successful diagnostic uses plans terminology')
  local first,second=F.db.recipes[2660],F.db.recipes[2661]

  changing=true
  eq(F.ReadRecipes(),0,'API source-changing state blocks import without an event')
  eq(F.db.recipes[2660],first,'API source-changing state preserves existing records')
  eq(F.db.lastImportAttempt.reason,'not_ready','source-changing refusal has a saved reason')
  changing=false; ready=false
  eq(F.ReadRecipes(),0,'false readiness postpones import')
  eq(F.db.lastImportAttempt.ready,false,'false readiness is retained in diagnostics')
  eq(F.db.recipes[2661],second,'false readiness leaves cached learned entry intact')
  ready=true
  eq(F.ReadRecipes(),2,'later readiness permits Refresh without reopening')

  fire('TRADE_SKILL_DATA_SOURCE_CHANGING')
  eq(F.ReadRecipes(),2,'current not-changing API answer clears a missed event latch')
  eq(F.recipeSourceChanging,false,'successful recovery clears stale changing flag')
  local changingAPI=C_TradeSkillUI.IsDataSourceChanging
  C_TradeSkillUI.IsDataSourceChanging=nil
  fire('TRADE_SKILL_DATA_SOURCE_CHANGING'); ready=false
  eq(F.ReadRecipes(),0,'event latch and false readiness defer import')
  ready=true
  eq(F.ReadRecipes(),2,'true readiness can recover without IsDataSourceChanging API')
  C_TradeSkillUI.IsDataSourceChanging=changingAPI

  second=F.db.recipes[2661]; rows[2661].learned=false; missingOwner=2661
  eq(F.ReadRecipes(),1,'one loading owner does not block other verified plans')
  eq(F.db.recipes[2661],second,'loading owner preserves complete cached plan')
  eq(F.db.recipes[2661].learned,true,'loading owner cannot erase cached learned state')
  eq(F.db.lastImportAttempt.reason,'partial','partial import retains its distinct result')
  eq(F.db.lastImportAttempt.loadingCount,1,'partial import records skipped entry count')
  eq(F.db.lastImportAttempt.why:find('Imported 1 Blacksmithing plan.',1,true)~=nil,true,'single-plan import uses singular wording')
  eq(F.db.lastImportAttempt.failedRecipeID,2661,'partial import records first loading entry')
  eq(F.recipeImportStatus:find('still loading',1,true)~=nil,true,'partial success keeps useful loading status')
  missingOwner='all'; first=F.db.recipes[2660]
  eq(F.ReadRecipes(),0,'all loading owners leave import pending')
  eq(F.db.lastImportAttempt.reason,'entries_loading','all loading owners have a clear recorded cause')
  eq(F.db.recipes[2660],first,'all loading owners preserve prior complete entries')
  missingOwner=nil; missingInfo=2661
  eq(F.ReadRecipes(),1,'one missing information row allows other validated plans')
  eq(F.db.recipes[2661],second,'missing information preserves complete saved entry')
  missingInfo=nil; missingSchematic=2661
  eq(F.ReadRecipes(),1,'one missing schematic allows other validated plans')
  eq(F.db.recipes[2661],second,'missing schematic preserves complete saved ingredients')
  missingSchematic=nil; missingReagents=2661
  eq(F.ReadRecipes(),1,'loading reagent quantities do not overwrite complete entries')
  eq(F.db.recipes[2661],second,'empty partial reagent list keeps previous complete entry')
  missingReagents=nil; rows[2661].learned=true
  currencyReagent=2661
  eq(F.ReadRecipes(),2,'explicit unsupported currency entry remains in catalogue')
  eq(F.db.recipes[2661].problem,'Unsupported reagent choices or currency','currency restriction has its specific explanation')
  currencyReagent=nil; rows[2661].output=nil; missingReagents=2661
  eq(F.ReadRecipes(),2,'non-item crafting entry remains in catalogue without reagents')
  eq(F.db.recipes[2661].problem,'No auctionable item output','non-item entry keeps its output explanation')
  rows[2661].output=2851; missingReagents=nil; F.ReadRecipes()

  first=F.db.recipes[2660]; second=F.db.recipes[2661]; changeCounter=true
  eq(F.ReadRecipes(),0,'selected child sourceCounter change discards complete pending batch')
  eq(F.db.recipes[2660],first,'counter change cannot commit first pending plan')
  changeCounter=false; childID=3001; childParent=164; changeChild=true
  eq(F.ReadRecipes(),0,'raw child switch under the same parent discards pending batch')
  eq(F.db.recipes[2661],second,'same-parent child switch cannot commit pending plan')
  changeChild=false; childID=164; childParent=nil; foreignOwner=2661
  eq(F.ReadRecipes(),0,'known foreign profession still rejects the whole batch')
  eq(F.db.recipes[2660],first,'known mismatch never partially commits earlier rows')
  eq(F.db.lastImportAttempt.ownerID,185,'mismatch diagnostic records actual owner')
  eq(F.db.lastImportAttempt.failedRecipeID,2661,'mismatch diagnostic records offending entry')
  foreignOwner=nil; childID=0; baseID=164
  eq(F.ReadRecipes(),2,'empty child info falls back to valid base like Blizzard')
  eq(F.db.lastImportAttempt.source,'base','fallback diagnostic identifies base source')

  ids=nil
  eq(F.ReadRecipes(),0,'unavailable list yields an explained empty import')
  eq(F.db.lastImportAttempt.reason,'list_loading','unavailable list retains a diagnostic')
  ids={}
  eq(F.ReadRecipes(),0,'empty list yields an explained empty import')
  eq(F.db.lastImportAttempt.reason,'empty_list','empty list retains a diagnostic')
  ids={2660,2661}; baseID=0
  eq(F.ReadRecipes(),0,'both invalid profession identities reject import')
  eq(F.db.lastImportAttempt.reason,'profession_loading','invalid profession identity has repair guidance')
  attempt=F.db.lastImportAttempt
  local status=F.recipeImportStatus
  ProfessionsFrame:Hide(); fire('TRADE_SKILL_CLOSE')
  eq(F.ReadRecipes(),0,'closed profession uses saved data')
  eq(F.db.lastImportAttempt,attempt,'closed Refresh preserves the meaningful active attempt')
  eq(F.recipeImportStatus,status,'closed Refresh preserves useful failure explanation')
end
