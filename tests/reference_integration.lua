-- Character evidence controls crafting; reference research stays distinct in UI.
return function(F,eq,fire,widget)
  local saved={}
  for _,key in ipairs({'db','filter','currentProfessions','currentProfessionsComplete','ItemInfo','Quote','ForecastQuote','CatalogueRecipes',
      'ReadRecipes','RefreshCatalogue','CatalogueStatusText','worthLearning','activeTab','page','priceCache','excluded','results',
      'detailRecipe','detailLearningItemID','detailLearningSource','detailLearningMode','reportData','currentWindow'}) do saved[key]={F[key]} end
  local oldDB=MobAuctionDB
  MobAuctionDB={setupComplete=true,scanForecastsEnabled=true,strictCosts=false,assumedDeposit=100,
    selectedProfessions={[185]=true},detectedSkills={[185]=244}}
  F.Init(); F.filter=185; F.currentProfessions={[185]=244}; F.currentProfessionsComplete=true
  F.ItemInfo=function(id) return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,1,7,0,0 end
  F.Quote=function(id,quantity,reagent)
    return quantity*(id==100 and 900 or 70),'Test snapshot','Forecast quantities',{kind='estimate'}
  end
  F.ForecastQuote=F.Quote
  local references={}
  for i=1,27 do
    local id=500+i
    references[id]={id=id,name=string.format('Cooking %02d',i),profession=185,output=100,made=1,
      reagents={{itemID=200,qty=2}},observedBuild=F.Build(),professionVerified=true,reader='catalogue',referenceOnly=true}
  end
  local known=references[501]
  known.learned=true; known.knowledgeVerified=true; known.observedSkill=244
  references[526].learned=true -- A knowledge claim without character evidence cannot be craftable.
  references[527].databaseReference=true; references[527].observedBuild=nil
  references[527].professionVerified=false; references[527].databaseSource='Recipe Registry Forever'
  references[527].databaseRequiredSkill=150
  F.CatalogueRecipes=function() return references end
  F.CatalogueStatusText=function() return 'Test reference catalogue' end
  F.ReadRecipes=function() return 0 end
  F.RefreshCatalogue=function() return false end
  local older={id=501,name='Wrong older import',profession=164,output=101,made=1,learned=true,
    reagents={{itemID=201,qty=9}},observedBuild='old-build',importNeedsRefresh=true}
  F.db.recipes[501]=older

  eq(F.CraftingRecipes()[501],known,'verified learned reference replaces an unusable old import for craft evaluation')
  eq(F.CraftingRecipes()[502],nil,'unknown learned status reference is excluded from craftable recipes')
  eq(F.CraftingRecipes()[526],nil,'a reference learned flag without knowledge verification is insufficient')
  eq(F.CraftingRecipes()[527],nil,'database research is excluded from craftable recipes')
  eq(F.db.recipes[501],older,'merging craftable references does not overwrite the saved character import')
  local results=F.Results()
  eq(#results,1,'only a reference with independently verified character knowledge reaches Crafting')
  eq(results[1].recipe.id,501,'Crafting selects the known reference recipe')
  eq(results[1].cost,140,'known reference uses its current two-unit reagent requirement')
  eq(results[1].profit,715,'known reference profit uses its current output and reagent facts')
  eq(results[1].estimated,true,'known reference snapshot prices retain forecast evidence')
  known.learned=false
  eq(#F.Results(),0,'current unlearned evidence overrides an older known import')
  known.learned=true
  eq(F.ScanStatus():find('additional learned reference',1,true)~=nil,true,'scan help explains the ready reference even when saved imports are stale')
  F.db.skills[185]=243
  eq(#F.Results(),0,'manual skill below observed reference rank excludes the craft')
  F.db.skills[185]=nil
  F.currentProfessions={}
  eq(#F.Results(),0,'a reference cannot keep a lost profession craftable')
  F.currentProfessions={[185]=244}

  -- An import can have a verified profession but still belong to an old client
  -- build. It must not conceal a newer current reference in the catalogue.
  older.professionVerified=true; older.importNeedsRefresh=nil
  F.worthLearning=false; F.activeTab='crafting'; F.page=1
  F.Open(); F.ShowCatalogue()
  eq(#F.reportData.actions,27,'catalogue merges reference research and old imports without duplicate IDs')
  eq(F.reportData.actions[1].label:find('Cooking 01 - Known',1,true)~=nil,true,'catalogue reports independently known reference clearly')
  eq(F.reportData.actions[2].label:find('Learning status unknown',1,true)~=nil,true,'unknown reference is never labeled unlearned')
  eq(F.reportData.actions[27].label:find('Reference database forecast',1,true)~=nil,true,'database catalogue rows disclose their reference provenance')
  older.observedBuild=F.Build(); older.observedAt=1
  F.ShowCatalogue()
  eq(F.reportData.actions[1].label:find('Cooking 01 - Known',1,true)~=nil,true,'fresh verified knowledge takes precedence over an older same-build import in Catalogue')
  older.observedBuild='old-build'
  eq(F.reportData.page,1,'reference catalogue begins on its first page')
  F.reportNext.scripts.OnClick()
  eq(F.reportData.page,2,'reference catalogue pages beyond the first twenty rows')
  eq(F.reportRows[1].text:GetText():find('Cooking 21',1,true)~=nil,true,'next reference page shows the correct recipe')
  eq(F.reportRows[8]:IsShown(),false,'last reference page hides rows beyond its seven results')
  F.reportPrevious.scripts.OnClick()
  F.reportRows[1].scripts.OnClick(F.reportRows[1])
  eq(F.detailRecipe,known,'known reference detail preserves the selected current reference over its stale saved import')
  eq(F.detailRecipe.output,100,'known reference detail does not revert to the older imported output')
  eq(F.detailRows[1].itemID,200,'known reference detail shows the current ingredient item')
  eq(F.detailRows[1].text:GetText():find('2 x',1,true)~=nil,true,'known reference detail shows the current ingredient quantity')
  eq(F.detailLearningMode,false,'known reference details remain ordinary craft details')
  eq(F.bestBatchButton:IsShown(),true,'known reference retains batch planning controls')

  F.ShowCatalogue(); F.reportRows[2].scripts.OnClick(F.reportRows[2])
  eq(F.detailRecipe.id,502,'unknown reference opens its own details')
  eq(F.detailLearningSource,'catalogue','unknown reference opens as research rather than owned crafting')
  eq(F.detailLearningMode,true,'unknown reference detail uses one-craft learning mode')
  eq(F.bestBatchButton:IsShown(),false,'learning research hides owned-craft batch planning')
  local research=F.EvaluateCatalogueLearning(502)
  eq(research.canLearn,false,'unknown character knowledge cannot earn a learning recommendation')
  eq(research.candidate,false,'unknown reference cannot become a checked Worth Learning flag')
  eq(research.profit,715,'unknown reference can still show a useful separate craft profit forecast')
  eq(F.db.recipes[502],nil,'research evaluation never saves unknown reference as a learned import')

  for key,value in pairs(saved) do F[key]=value[1] end
  MobAuctionDB=oldDB
end
