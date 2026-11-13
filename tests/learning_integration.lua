-- Trainer and AH learning rows use the same one-craft calculation and UI.
-- Search/mapping contracts are tested separately; this exercises their UI boundary.
return function(F,eq)
  local functionKeys={'Quote','Deposit','ItemName','AuctionLearningRows','EvaluateAuctionLearning',
    'AuctionLearningStatus','ScanAuctionRecipes','MoreAuctionRecipes','RequestDepth'}
  local saved={}
  for _,key in ipairs(functionKeys) do saved[key]=F[key] end
  local oldDB,oldFilter,oldCurrent,oldComplete=F.db,F.filter,F.currentProfessions,F.currentProfessionsComplete
  local oldWorth,oldTab=F.worthLearning,F.activeTab
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[185]=true},detectedSkills={[185]=244},crafts=7}
  F.Init(); F.filter=185; F.currentProfessions={[185]=244}; F.currentProfessionsComplete=true
  local function recipe(id,name,training)
    local r={id=id,name=name,profession=185,learned=false,professionVerified=true,observedBuild=F.Build(),
      output=100000+id,made=1,reagents={{itemID=200000+id,qty=1}}}
    if training then
      r.trainingCost=training; r.trainerAvailable=true; r.trainerSeen=time(); r.trainerName='Cooking Trainer'
      F.db.requirements[id]={rank=100,build=F.Build()}
    end
    F.db.recipes[id]=r
    return r
  end
  local cheap=recipe(501,'Small trainer craft',1)
  local costly=recipe(502,'Better trainer craft',500000)
  local auction=recipe(503,'Best auction craft')
  local pending=recipe(504,'Deposit loading craft')
  local values={[100501]=600,[100502]=1000,[100503]=2000,[100504]=500}
  local acquisitionPrice=900000
  F.Quote=function(id,quantity,reagent)
    if reagent then return 100*quantity,'Checked ingredients',nil,{kind='depth'} end
    return values[id] and values[id]*quantity,'Recent output price'
  end
  F.Deposit=function(id,quantity)
    if id==100504 then return nil,'Deposit loading' end
    return 10*quantity,'Game quote'
  end
  F.ItemName=function(id) return 'Item '..id end
  local function auctionRow(r,itemID)
    local settings={}; for key,value in pairs(F.db) do settings[key]=value end; settings.crafts=1
    local row=F.Evaluate(r,settings,F.Quote,F.Deposit)
    row.acquisition='auction'; row.acquisitionItemID=itemID; row.acquisitionName='Recipe: '..r.name
    row.acquisitionPrice=r==auction and acquisitionPrice or nil
    row.acquisitionPriceSource='Current recipe listing'; row.canLearn=true
    row.candidate=r==auction; row.pending=r==auction and {} or {'Deposit unavailable'}
    row.status=r==auction and 'Worth learning' or 'Need deposit'
    return row
  end
  F.AuctionLearningRows=function() return {auctionRow(auction,900503),auctionRow(pending,900504)} end
  F.EvaluateAuctionLearning=function(itemID)
    if itemID==900503 then return auctionRow(auction,itemID) end
    if itemID==900504 then return auctionRow(pending,itemID) end
  end
  F.AuctionLearningStatus=function() return 'Two recipe listings observed.' end
  local scans,pages,requested=0,0,{}
  F.ScanAuctionRecipes=function() scans=scans+1 end
  F.MoreAuctionRecipes=function() pages=pages+1 end
  F.RequestDepth=function(id) requested[#requested+1]=id end

  local rows=F.WorthLearning()
  eq(#rows,4,'trainer and auction learning candidates share one list')
  eq(rows[1].recipe,auction,'highest one-craft profit ranks first despite expensive recipe purchase')
  eq(rows[1].adjusted,1790,'learning profit deducts materials cut and failed deposit only')
  eq(rows[1].quantity,1,'auction recommendation evaluates one craft')
  eq(rows[2].recipe,costly,'higher trainer craft profit outranks cheaper training')
  eq(rows[2].adjusted,840,'trainer price is not deducted from craft profit')
  eq(rows[2].acquisitionPrice,500000,'trainer acquisition price remains available separately')
  eq(rows[3].recipe,cheap,'small trainer profit follows larger trainer profit')
  eq(rows[4].adjusted,nil,'missing deposit remains unknown after row integration')
  eq(F.db.crafts,7,'one-craft comparison does not overwrite the ordinary batch size')
  eq(F.db.includeUnlearned,false,'learning comparison restores the crafting eligibility setting')
  values[100504]=3000
  eq(F.WorthLearning()[1].recipe,pending,'Sale profit order includes a higher sale profit even while its deposit loads')
  values[100504]=500
  acquisitionPrice=1; costly.trainingCost=1; cheap.trainingCost=900000
  rows=F.WorthLearning()
  eq(rows[1].recipe,auction,'changing purchase prices cannot change the profit ranking')
  eq(rows[2].adjusted,840,'changing training price cannot change craft profit')

  F.activeTab='crafting'; F.worthLearning=true; F.page=1; F.Open()
  eq(F.rows[1].result.recipe,auction,'learning page displays the combined sorted results')
  eq(F.materialHeader.text,'Learn price','learning page labels its acquisition-price column')
  eq(F.saleHeader.text,'Profit / craft','learning page labels its one-craft profit column')
  eq(F.rows[1].fields[2].text,F.Money(1),'learning page displays recipe purchase cost separately')
  eq(F.rows[1].fields[3].text:find(F.Money(1790),1,true)~=nil,true,'learning page displays profit without acquisition deduction')
  eq(F.rows[4].fields[2].text,'?','unknown recipe purchase price cannot display the material cost instead')
  eq(F.rows[4].fields[6].text,'Need deposit','pending learning evidence remains visible')
  eq(F.recipeHint.text:find('Recipe price is separate.',1,true)~=nil,true,'learning page explains the price distinction')
  eq(F.moreRecipesButton:IsShown(),true,'learning mode exposes browse pagination')
  eq(F.craftAmountControls[1]:IsShown(),false,'learning mode hides ordinary batch controls')
  F.costButton.scripts.OnClick()
  eq(F.learningOnlyAH,true,'learning source toggle selects only auction recipe offers')
  eq(#F.results,2,'AH-only view excludes trainer entries')
  F.costButton.scripts.OnClick()
  eq(F.learningOnlyAH,false,'learning source toggle restores all acquisition sources')
  eq(#F.results,4,'all-source view restores trainer and auction recipes')

  F.rows[1].scripts.OnClick()
  eq(F.details:IsShown(),true,'clicking an auction recipe opens its details')
  eq(F.window:IsShown(),false,'recipe details do not overlap the opportunities page')
  eq(F.detailLearningItemID,900503,'auction detail retains the purchased recipe item ID')
  eq(F.detailTitle.text:find('| 1 craft |',1,true)~=nil,true,'learning detail uses one craft despite batch setting seven')
  eq(F.detailRows[1].itemID,900503,'first learning detail row is the recipe purchase')
  eq(F.detailRows[2].itemID,200503,'ingredient details follow the recipe purchase')
  F.detailRows[1].check.scripts.OnClick(); F.detailRows[2].check.scripts.OnClick()
  eq(requested[1],900503,'purchase Check requests the recipe item listings')
  eq(requested[2],200503,'ingredient Check requests the reagent listings')
  eq(F.detailSummary.text:find('(excluded from profit)',1,true)~=nil,true,'detail summary explicitly separates acquisition price')
  eq(F.bestBatchButton:IsShown(),false,'learning detail does not offer a conflicting batch-size calculation')
  F.details:Hide()
  eq(F.window:IsShown(),true,'closing learning detail returns to the list')
  F.rows[2].scripts.OnClick()
  eq(F.detailLearningMode,true,'trainer row also opens a learning detail')
  eq(F.detailLearningItemID,nil,'trainer row does not retain the previous auction item')
  eq(F.detailTitle.text:find('| 1 craft |',1,true)~=nil,true,'trainer detail keeps the same one-craft comparison')
  eq(F.detailRows[1].itemID,200502,'trainer detail begins with its reagent instead of the earlier auction recipe')

  F.worthLearning=false; F.ShowDetails(cheap)
  eq(F.detailLearningMode,false,'ordinary recipe detail clears learning mode')
  eq(F.detailTitle.text:find('| 7 crafts |',1,true)~=nil,true,'ordinary details restore the configured craft batch')
  eq(F.detailRows[1].itemID,200501,'ordinary details have no stale recipe purchase row')
  eq(F.bestBatchButton:IsShown(),true,'ordinary details restore batch planning')
  F.details:Hide(); F.Open()
  eq(F.materialHeader.text,'Materials','ordinary crafting restores its material cost column')
  eq(F.moreRecipesButton:IsShown(),false,'ordinary crafting hides learning browse pagination')
  eq(F.craftAmountControls[1]:IsShown(),true,'ordinary crafting restores batch controls')

  for _,key in ipairs(functionKeys) do F[key]=saved[key] end
  F.db=oldDB; MobAuctionDB=oldDB; F.filter=oldFilter; F.currentProfessions=oldCurrent; F.currentProfessionsComplete=oldComplete
  F.worthLearning=oldWorth; F.activeTab=oldTab; F.detailRecipe=nil; F.detailLearningItemID=nil; F.detailLearningMode=false
end
