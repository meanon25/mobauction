-- Profession-specific wording follows the viewed data and survives paging.
return function(F, eq)
  local readRecipes=F.ReadRecipes
  F.ReadRecipes=function() return 0 end
  eq(F.db.loadedVersion,F.VERSION,'startup records the addon version that actually loaded')
  F.db.selectedProfessions={[164]=true,[185]=true}
  F.db.skills={}; F.db.detectedSkills={[164]=190,[185]=244}
  F.currentProfessions={[164]=190,[185]=244}; F.currentProfessionsComplete=true
  F.db.recipes={}
  for id=18001,18025 do
    F.db.recipes[id]={id=id,name='Smithing item '..id,profession=164,learned=true,
      observedBuild=F.Build(),observedSkill=190,output=100,made=1,reagents={{itemID=200,qty=1}}}
  end
  F.db.recipes[2538]={id=2538,name='Charred Wolf Meat',profession=185,learned=true,
    observedBuild=F.Build(),observedSkill=244,output=2679,made=1,reagents={{itemID=2672,qty=1}}}
  F.activeTab='crafting'; F.worthLearning=false; F.filter=164
  F.Open()
  eq(F.recipeHeader.text,'Plan','Blacksmithing list identifies plans')
  eq(F.recipeHint.text:find('Click a plan',1,true)~=nil,true,'Blacksmithing hint uses plan wording')
  F.ShowDetails(F.db.recipes[18001])
  eq(F.detailTitle.text:find('plan ID 18001',1,true)~=nil,true,'Blacksmithing details identify plan ID')
  F.ShowCatalogue()
  eq(F.report.TitleText.text,'MobAuction - Blacksmithing plan catalogue','Blacksmithing catalogue names its profession and plans')
  eq(F.reportPage.text,'25 plans | page 1/2','Blacksmithing catalogue counts plans')
  F.reportNext.scripts.OnClick()
  eq(F.reportPage.text,'25 plans | page 2/2','catalogue paging retains plan terminology')
  F.filter=185; F.Open()
  eq(F.recipeHeader.text,'Recipe','switching to Cooking restores recipe heading')
  F.ShowDetails(F.db.recipes[2538])
  eq(F.detailTitle.text:find('recipe ID 2538',1,true)~=nil,true,'Cooking details retain recipe terminology')
  F.filter=nil; F.Open(); F.ShowCatalogue()
  eq(F.report.TitleText.text,'MobAuction - Recipe catalogue','all-profession catalogue keeps generic wording')
  eq(F.reportPage.text,'26 recipes | page 1/2','mixed catalogue retains generic recipe count')
  F.filter=164; F.ShowDeals()
  eq(F.report.TitleText.text,'MobAuction - Recipe deals','all-profession deal feature stays Recipe deals')

  -- Reproduce the confusing count: a large Cooking catalogue must not read as
  -- 135 Blacksmithing plans or report Cooking exclusions as smithing problems.
  F.db.recipes={}; F.recipeImportStatus=nil
  for id=19001,19135 do
    local row={id=id,name='Cooking item '..id,profession=185,learned=true,
      observedBuild=F.Build(),observedSkill=999,output=100,made=1,reagents={{itemID=200,qty=1}}}
    if id%3==0 then row.observedBuild='old build'
    elseif id%3==1 then row.problem='Missing Cooking reagents' end
    F.db.recipes[id]=row
  end
  local status=F.ScanStatus()
  eq(status:match('^[^\n]+'),'Blacksmithing: 0 plans saved; 0 ready for price searches.','selected profession count cannot include other professions')
  eq(status:find('Across all professions: 135 saved entries.',1,true)~=nil,true,'global catalogue count is explicitly separate')
  eq(status:find('above your selected skill',1,true),nil,'Cooking rank exclusions are not attributed to Blacksmithing')
  eq(status:find('need their recipe data refreshed',1,true),nil,'stale Cooking rows are not reported as Blacksmithing refresh failures')
  eq(status:find('have missing or unsupported recipe data',1,true),nil,'Cooking reagent problems are not attributed to Blacksmithing')
  F.ShowCatalogue()
  eq(F.reportPage.text,'0 plans | page 1/1','empty Blacksmithing catalogue counts no Cooking rows')
  F.filter=nil; F.ShowCatalogue()
  eq(F.reportPage.text,'135 recipes | page 1/7','all-profession catalogue exposes the separate imported entries')
  F.db.recipes[18001]={id=18001,name='A known smithing item',profession=164,learned=true,
    observedBuild=F.Build(),observedSkill=190,output=100,made=1,reagents={{itemID=200,qty=1}}}
  F.filter=164
  eq(F.ScanStatus():match('^[^\n]+'),'Blacksmithing: 1 plan saved; 1 ready for price searches.','selected plan count and eligible count use Blacksmithing only')
  F.ShowCatalogue()
  eq(F.reportPage.text,'1 plan | page 1/1','single-plan catalogue count uses singular wording')
  local say,message=F.Say
  F.Say=function(value) message=value end
  F.ReadRecipes=function()
    F.db.lastImportAttempt={why='Imported 1 Blacksmithing plan.'}
    return 1
  end
  eq(F.RefreshRecipes(),1,'manual Refresh returns the actual imported count')
  eq(message,'Imported 1 Blacksmithing plan.','manual Refresh confirms the current import result')
  F.ReadRecipes=function() return 0 end
  F.RefreshRecipes()
  eq(message:find('Using saved plans.',1,true)~=nil,true,'closed-window Refresh explains it uses saved plans')
  F.Say=say
  F.ReadRecipes=readRecipes
end
