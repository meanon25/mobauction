-- Headless contract tests. No game client, live AH requests or external services.
local F, frames, messages = {}, {}, {}
local count = 0
local function eq(actual, expected, message)
  count=count+1
  assert(actual==expected,(message or '')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local methods={}
setmetatable(methods,{__index=function() return function() end end})
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:SetText(text) self.text=text end
function methods:GetText() return self.text end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked end
function methods:Show() local changed=not self.visible; self.visible=true; if changed and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() local changed=self.visible; self.visible=false; if changed and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.visible end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetVerticalScroll(value) self.scroll=value end
function methods:Raise() self.raised=true end
function methods:HasFocus() return false end
function methods:GetStringHeight() return 100 end
local function widget()
  return setmetatable({scripts={},events={},text='',checked=false,visible=true},{__index=function(_,key)
    if key:match('^[A-Z]') then return methods[key] end
    return rawget(methods,key)
  end})
end
function methods:CreateFontString() return widget() end
function CreateFrame(_,name)
  local w=widget(); w.TitleText=widget(); w.name=name; frames[#frames+1]=w; return w
end
local function fire(event,...)
  if event=='AUCTION_HOUSE_SHOW' and AuctionHouseFrame then AuctionHouseFrame:Show()
  elseif event=='AUCTION_HOUSE_CLOSED' and AuctionHouseFrame then AuctionHouseFrame:Hide() end
  for _,frame in ipairs(frames) do if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end end
end
UIParent=widget(); UISpecialFrames={}; SlashCmdList={}; GameTooltip=widget()
AuctionHouseFrame=widget(); AuctionHouseFrame:Hide()
unpack=unpack or table.unpack
local now=1000000
function time() return now end
local build='70532'
function GetBuildInfo() return '1.60.1',build end
function UnitName() return 'Test Trainer' end
local detected={{'Alchemy',150,171},{'Mining',100,186},{'Cooking',80,185},{'First Aid',50,129}}
function GetProfessions() return 1,2,nil,3,4 end
function GetProfessionInfo(i) local p=detected[i]; return p[1],nil,p[2],300,nil,nil,p[3] end
Enum={CraftingReagentType={Basic=0},ItemCommodityStatus={Commodity=2}}
C_Item={GetItemInfo=function(id)
  if id==999 then return nil end
  -- GetItemInfo: vendor sell price=11, class=12, subclass=13, bind=14.
  return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,9,id==900 and 9 or (id==1001 and 12 or 7),id==900 and 6 or 0,id==1000 and 1 or 0
end,RequestLoadItemDataByID=function() end}
local prices,ages={[100]=1000,[101]=1500,[200]=20,[201]=30},{[100]=0,[101]=0,[200]=0,[201]=0}
local searchTerms
Auctionator={API={v1={
  GetAuctionPriceByItemID=function(_,id) return prices[id] end,
  GetAuctionAgeByItemID=function(_,id) return ages[id] end,
  MultiSearchExact=function(_,terms) searchTerms=terms end,
}}}
local ledger={[900]={median7d=10000,updated=now,snapshot=false},[200]={minBuyout=25,updated=now,snapshot=false}}
AHledgerAPI={GetPrice=function(id) return ledger[id] end}
local commodity,items,full,browse={}, {}, {}, {}
local requests,moreRequests=0,0
C_AuctionHouse={
  MakeItemKey=function(id) return {itemID=id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0} end,
  GetItemKeyInfo=function(key) return {isCommodity=key.itemID~=201} end,
  CalculateCommodityDeposit=function(_,duration,quantity) return duration*quantity*2 end,
  HasFullCommoditySearchResults=function(id) return full[id] end,
  HasFullItemSearchResults=function(key) return full[key.itemID] end,
  GetNumCommoditySearchResults=function(id) return #(commodity[id] or {}) end,
  GetNumItemSearchResults=function(key) return #(items[key.itemID] or {}) end,
  GetCommoditySearchResultInfo=function(id,i) return commodity[id][i] end,
  GetItemSearchResultInfo=function(key,i) return items[key.itemID][i] end,
  SendSearchQuery=function() requests=requests+1 end,
  RequestMoreCommoditySearchResults=function() moreRequests=moreRequests+1 end,
  RequestMoreItemSearchResults=function() moreRequests=moreRequests+1 end,
  IsThrottledMessageSystemReady=function() return true end,
  GetBrowseResults=function() return browse end,
}
local profession=171
local definitions={
  [1]={name='Known craft',learned=true,output=100,qty=2},
  [2]={name='Unlearned craft',learned=false,output=101,qty=3},
  [3]={name='Enchant service',learned=true,qty=2},
}
C_TradeSkillUI={
  GetBaseProfessionInfo=function() return {professionID=profession,professionName=F.professions[profession],skillLevel=150} end,
  GetProfessionInfoByRecipeID=function() return {professionID=profession} end,
  GetAllRecipeIDs=function() return {1,2,3} end,
  GetRecipeInfo=function(id) return definitions[id] end,
  GetRecipeSchematic=function(id) local r=definitions[id]; return {outputItemID=r.output,quantityMin=1,quantityMax=2,
    reagentSlotSchematics={{reagentType=0,quantityRequired=r.qty,reagents={{itemID=200}}}}} end,
}
for line in io.lines('MobAuction/MobAuction.toc') do
  if line:match('%.lua$') then assert(loadfile('MobAuction/'..line))('MobAuction',F) end
end
F.Say=function(message) messages[#messages+1]=message end
MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false}
fire('ADDON_LOADED','MobAuction')
eq(F.db,MobAuctionDB,'startup initialization')
eq(SLASH_MOBAUCTION1,'/moba','requested command')
eq(SLASH_MOBAUCTION2,'/mobauction','long alias')
for key,value in pairs(_G) do if type(key)=='string' and key:match('^SLASH_MOBAUCTION') then assert(value~='/ma' and value~='/fp') end end
SlashCmdList.MOBAUCTION('')
eq(F.setup:IsShown(),true,'first launch asks for professions')
eq(F.window,nil,'setup precedes main window')
local found=F.DiscoverProfessions()
eq(found[171],150,'primary profession detected')
eq(found[185],80,'secondary profession detected after nil slot')
eq(found[129],50,'First Aid detected')
eq(F.SaveSetup({},{}),false,'empty setup rejected')
eq(F.SaveSetup({[171]=true},{[171]='2.5'}),false,'fractional skill rejected')
eq(F.db.setupComplete,nil,'failed setup does not save')
eq(F.SaveSetup({[171]=true,[185]=true},{[171]='150',[185]='80'}),true,'character setup saved')
F.Open(); eq(#F.rows,10,'main interface built')
fire('TRADE_SKILL_SHOW')
eq(F.db.recipes[1].profession,171,'all professions import: Alchemy')
eq(F.db.recipes[2].learned,false,'unlearned catalogue retained')
eq(F.db.recipes[3].problem,'No auctionable item output','non-item output explained')
eq(F.db.recipes[1].made,1,'minimum yield used')
eq(F.Eligible(F.db.recipes[1]),true,'learned at observed skill allowed')
F.SetSkill(171,'149'); eq(F.Eligible(F.db.recipes[1]),false,'unknown minimum not invented below observed skill')
F.SetSkill(171,'150')
eq(F.RequiredSkill(F.db.recipes[1]),nil,'Classic fallback no longer verifies minimum')
F.db.requirements[1]=1; eq(F.RequiredSkill(F.db.recipes[1]),nil,'old unversioned override not verified')
SlashCmdList.MOBAUCTION('requirement 1 100')
eq(F.RequiredSkill(F.db.recipes[1]),100,'manual build-specific requirement')
F.SetSkill(171,'100'); eq(F.Eligible(F.db.recipes[1]),true,'exact minimum boundary')
F.SetSkill(171,'99'); eq(F.Eligible(F.db.recipes[1]),false,'above skill filtered')
F.SetSkill(171,'150'); build='changed'
eq(F.Eligible(F.db.recipes[1]),false,'recipe observation invalidated by build change')
eq(F.RequiredSkill(F.db.recipes[1]),nil,'manual verification invalidated by build change')
build='70532'
profession=333; F.ReadRecipes(); eq(F.db.recipes[1].profession,333,'Enchanting imported')
eq(F.Eligible(F.db.recipes[1]),false,'unselected profession filtered')
profession=171; F.ReadRecipes()
local recipe=F.db.recipes[1]
local settings={crafts=2,cut=5,failures=1,duration=1}
local q=function(id,n) return (id==100 and 1000 or 20)*n end
local r=F.Evaluate(recipe,settings,q,function() return 10 end)
eq(r.cost,80,'batch material cost'); eq(r.fee,100,'cut'); eq(r.profit,1820,'refunded deposit not charged')
eq(r.adjusted,1810,'failed listing deposit charged'); eq(r.capital,100,'cash includes failed and final deposit')
r=F.Evaluate(recipe,settings,function(id,n) if id==100 then return n*1000 end end,function() return 10 end)
eq(r.profit,nil,'missing ingredient blocks profit')
r=F.Evaluate(F.db.recipes[3],settings,q,function() return 0 end)
eq(r.profit,nil,'unsupported recipe safe in details')
local duplicate={output=100,made=1,reagents={{itemID=200,qty=2},{itemID=200,qty=3}}}
r=F.Evaluate(duplicate,settings,q,function() return 0 end)
eq(#r.lines,1,'duplicate reagent slots aggregated')
eq(r.lines[1].quantity,10,'aggregated total demand')
-- Exact tier pricing and mixed vendor purchases.
local book={complete=true,kind='commodity',lots={{price=10,quantity=2},{price=100,quantity=10}}}
eq(F.DepthCost(book,5),320,'cheap first units do not price whole batch')
eq(F.DepthCost(book,13),nil,'insufficient stock')
eq(F.DepthCost(book,7,{price=150,bundle=5}),170,'mix cheap AH units with vendor bundle')
eq(F.DepthCost(nil,6,{price=12,bundle=5}),24,'whole vendor bundles')
book.complete=false; eq(F.DepthCost(book,2),nil,'partial listing data excluded'); book.complete=true
local stacks={complete=true,kind='item',lots={{price=50,quantity=5},{price=80,quantity=10},{price=5,quantity=1}}}
eq(F.DepthCost(stacks,6),55,'whole stack combinatorial choice')
eq(F.DepthCost(stacks,2),50,'cannot split stack')
eq(F.DepthCost(stacks,17),nil,'whole stack shortage')
eq(F.DepthCost(stacks,1001),nil,'large stack calculation bounded')
-- Compare optimized commodity/vendor plan against exhaustive supplier bundle enumeration.
for qty=1,35 do
  local vendor={price=37,bundle=4}
  local test={complete=true,kind='commodity',lots={{price=3,quantity=7},{price=9,quantity=8},{price=50,quantity=20}}}
  local expected=math.huge
  for bundles=0,math.ceil(qty/vendor.bundle) do
    local remaining,cost=math.max(0,qty-bundles*vendor.bundle),bundles*vendor.price
    for _,lot in ipairs(test.lots) do local n=math.min(remaining,lot.quantity); cost=cost+n*lot.price; remaining=remaining-n end
    if remaining==0 then expected=math.min(expected,cost) end
  end
  eq(F.DepthCost(test,qty,vendor),expected,'tier optimizer vs exhaustive '..qty)
end
fire('AUCTION_HOUSE_SHOW')
commodity[200]={{unitPrice=10,quantity=2},{unitPrice=100,quantity=10},{unitPrice=1,quantity=500,containsOwnerItem=true}}
full[200]=true; fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
eq(#F.depth[200].lots,2,'own auctions excluded')
eq(F.Quote(200,5,true),320,'quote uses captured depth')
eq(F.Quote(200,13,true),nil,'shortage cannot fall back to cached minimum')
F.db.strictCosts=false; eq(F.Quote(200,13,true),nil,'estimate mode still respects observed shortage')
now=now+61
eq(F.Quote(200,5,true),100,'expired data labelled estimate in estimate mode')
local _,_,_,evidence=F.Quote(200,5,true); eq(evidence.kind,'estimate','estimate provenance')
F.db.strictCosts=true; eq(F.Quote(200,5,true),nil,'strict mode rejects expired data')
full[200]=false; F.RequestDepth(200); fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
eq(F.Quote(200,1,true),nil,'incomplete page blocked')
F.RequestDepth(200); eq(moreRequests,1,'next click requests missing pages')
full[200]=true; fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
F.RequestDepth(201)
items[201]={{buyoutAmount=50,quantity=5,auctionID=1},{buyoutAmount=50,quantity=5,auctionID=1},{minBid=1,quantity=20,auctionID=2}}
full[201]=true; fire('ITEM_SEARCH_RESULTS_UPDATED',C_AuctionHouse.MakeItemKey(201))
eq(#F.depth[201].lots,1,'deduplicate auctions and exclude bid-only')
eq(F.Quote(201,2,true),50,'noncommodity quote buys whole lot')
fire('AUCTION_HOUSE_PURCHASE_COMPLETED',1); eq(next(F.depth),nil,'purchase invalidates depth')
F.db.vendors[200]={price=12,bundle=5,seen=now,name='Supplier'}
eq(F.Quote(200,6,true),24,'vendor still usable without depth')
F.db.vendors[200].seen=now-8*86400; eq(F.Quote(200,6,true),nil,'stale vendor excluded')
F.db.vendors[200]=nil
F.priceCache={}; ages[100]=10; eq(F.Quote(100,1,false),nil,'stale output price excluded'); ages[100]=0
F.priceCache={}; eq(F.Quote(1000,1,false),nil,'bound output excluded')
eq(F.Deposit(100,3,1),6,'correct isCommodity metadata field')
-- Trainer observations and worthwhile learning recommendations.
function GetNumTrainerServices() return 1 end
function GetTrainerServiceSkillReq() return 'Alchemy',125,true end
function GetTrainerServiceInfo() return 'Unlearned craft','available' end
function GetTrainerServiceCost() return 3000 end
C_TooltipInfo={GetTrainerService=function() return {id=2} end}
fire('TRAINER_SHOW')
eq(F.RequiredSkill(F.db.recipes[2]),125,'trainer verifies skill requirement')
eq(F.db.recipes[2].trainingCost,3000,'training cost recorded')
F.ReadRecipes(); eq(F.db.recipes[2].trainingCost,3000,'profession refresh preserves trainer observations')
F.db.includeUnlearned=true; eq(F.Eligible(F.db.recipes[2]),true,'verified trainable recipe eligible')
F.SetSkill(171,'124'); eq(F.Eligible(F.db.recipes[2]),false,'trainable recipe above selected skill excluded'); F.SetSkill(171,'150')
F.db.includeUnlearned=false; eq(F.Eligible(F.db.recipes[2]),false,'known view excludes unlearned')
commodity[200]={{unitPrice=20,quantity=100}}; full[200]=true; fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
F.db.crafts=2; F.priceCache={}
local worth=F.WorthLearning()
eq(#worth,1,'worth learning finds verified profitable recipe')
eq(worth[1].acquisitionPrice,3000,'recommendation displays learning cost separately')
eq(worth[1].adjusted,1363,'learning profit is one craft less materials, AH cut and failed deposit only')
eq(worth[1].afterTraining,nil,'learning price is never deducted from displayed craft profit')
eq(F.db.includeUnlearned,false,'recommendations preserve view setting')
F.db.recipes[2].trainerAvailable=false
local research=F.WorthLearning()
eq(#research,1,'unavailable training remains visible as catalogue research')
eq(research[1].acquisition,'catalogue','unavailable training is not presented as a trainer offer')
eq(research[1].canLearn,false,'unavailable training is not confirmed learnable')
F.db.recipes[2].trainerAvailable=true
F.ShowDetails(recipe); eq(F.details:IsShown(),true,'batch inspector opens')
F.RefreshDetails(); F.ShowCatalogue(); eq(F.report:IsShown(),true,'catalogue opens')
-- Recipe bargains use historical asking-price reference with clear scope and cooldown.
now=now+1; ledger[900].updated=now
browse={{itemKey={itemID=900},minPrice=5000}}
local before=#messages; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
eq(#messages,before+1,'recipe bargain alert')
eq(#F.DealList(),1,'recipe bargain retained')
eq(F.DealList()[1].matches,true,'matching profession marked')
fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED'); eq(#messages,before+1,'duplicate alert suppressed')
browse[1].minPrice=9500; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED'); eq(#F.DealList(),0,'price rise removes stale bargain')
eq(F.CheckRecipeDeal(200,1),nil,'non-recipe item never alerted')
ledger[900].snapshot=true; eq(F.CheckRecipeDeal(900,5000),nil,'seed snapshot excluded'); ledger[900].snapshot=false
ledger[900].median7d=nil; eq(F.CheckRecipeDeal(900,5000),nil,'no historical benchmark means no alert'); ledger[900].median7d=10000
SlashCmdList.MOBAUCTION('alerts off'); eq(F.db.dealAlerts,false,'alerts disabled')
SlashCmdList.MOBAUCTION('discount 50'); eq(F.db.dealPercent,50,'discount configured')
SlashCmdList.MOBAUCTION('saving 2000'); eq(F.db.dealSaving,2000,'minimum saving configured')
F.ShowDeals(); eq(F.report:IsShown(),true,'deals interface opens')
fire('AUCTION_HOUSE_CLOSED'); eq(next(F.depth),nil,'AH close clears depth'); eq(#F.DealList(),0,'AH close clears deals')
F.ScanCraftPrices(); eq(searchTerms,nil,'scan requires AH')
fire('AUCTION_HOUSE_SHOW'); F.ScanCraftPrices(); eq(#searchTerms,3,'scan includes known and unlearned catalogue outputs and reagent')
SlashCmdList.MOBAUCTION('skill alchemy 140'); eq(F.SkillLevel(171),140,'skill command for any profession')
SlashCmdList.MOBAUCTION('skill first aid 75'); eq(F.SkillLevel(129),75,'multiword profession command')
SlashCmdList.MOBAUCTION('skill alchemy auto'); eq(F.SkillLevel(171),150,'automatic skill restored')
F.Init(); eq(F.db.setupComplete,true,'setup survives reinitialization')
print('PASS: '..count..' checks (startup, all-profession setup, pricing, verification, learning, alerts and UI)')
-- Exercise onboarding controls and empty/partial API failure cases end to end.
F.ShowSetup()
local detectButton,saveButton
for _,frame in ipairs(frames) do
  if frame.text=='Detect my professions' then detectButton=frame end
  if frame.text=='Save character' then saveButton=frame end
end
assert(detectButton and saveButton)
detectButton.scripts.OnClick(detectButton)
eq(F.setupRows[186].check:GetChecked(),true,'setup Detect selects Mining')
eq(F.setupRows[129].input:GetText(),'50','setup Detect populates secondary skill')
saveButton.scripts.OnClick(saveButton)
eq(F.db.selectedProfessions[186],true,'setup Save persists detected selections')
eq(F.setup:IsShown(),false,'setup closes after saving')
function GetTrainerServiceCost() return 100,1,0 end
fire('TRAINER_SHOW'); eq(F.db.recipes[2].trainingCost,nil,'non-gold training cost excluded')
F.db.vendors[200]={price=12,bundle=5,seen=now,name='Supplier'}
local partial={complete=false,kind='commodity',seen=now,lots={{price=1,quantity=100}}}
F.depth[200]=partial
local total,_,_,kind=F.BatchQuote(200,6,F.db.vendors[200])
eq(total,24,'partial AH data may use full vendor purchase')
-- Whole-stack dynamic program agrees with exhaustive subsets, including vendor top-ups.
local lots={{price=12,quantity=3},{price=15,quantity=5},{price=7,quantity=1},{price=9,quantity=2}}
local v={price=11,bundle=2}
for wanted=1,15 do
  local expected=math.huge
  for mask=0,15 do
    local quantity,cost=0,0
    for i,lot in ipairs(lots) do if math.floor(mask/2^(i-1))%2==1 then quantity=quantity+lot.quantity; cost=cost+lot.price end end
    cost=cost+math.ceil(math.max(0,wanted-quantity)/v.bundle)*v.price
    expected=math.min(expected,cost)
  end
  eq(F.DepthCost({complete=true,kind='item',lots=lots},wanted,v),expected,'whole-stack optimization vs exhaustive '..wanted)
end
-- Farms: provider contracts, faction/level/access filters and reference math.
function UnitLevel() return 20 end
function UnitFactionGroup() return 'Alliance' end
F.ShowTab('farms')
eq(#F.farmRows,10,'farm tab built without optional providers')
eq(#F.farmResults,0,'no invented locations without provider')
eq(F.craftPanel:IsShown(),false,'farm tab hides crafting panel')
local farmNPCs={
  [1]={name='Low mob',level=10,rank=0,zone=1,rate=25},
  [2]={name='High mob',level=30,rank=0,zone=1,rate=80},
  [3]={name='Elite',level=10,rank=1,zone=1,rate=100},
  [4]={name='Friendly',level=10,rank=0,zone=1,friendly='A',rate=100},
  [5]={name='Dungeon mob',level=10,rank=0,zone=2,rate=100},
  [6]={name='Missing rate',level=15,rank=0,zone=1},
  [7]={name='No drop',level=10,rank=0,zone=1,rate=0},
  [8]={name='Bad rate',level=10,rank=0,zone=1,rate=101},
}
local farmItems={[200]={1,2,3,4,5,7},[201]={6},[1000]={1},[1001]={1},[999]={1}}
LibQuestieDB={RequireContract=function(v) return v==4 end,Item={npcDrops=function(id) return farmItems[id] end,
  objectDrops=function(id) if id==2770 then return {10} end end},Npc={},Object={
  name=function() return 'Gathering object' end,spawns=function() return {[1]={{45,55}}} end}}
for field,key in pairs({name='name',maxLevel='level',minLevel='level',rank='rank',friendlyToFaction='friendly'}) do
  LibQuestieDB.Npc[field]=function(id) return farmNPCs[id][key] end
end
LibQuestieDB.Npc.spawns=function(id) return {[farmNPCs[id].zone]={{42.5,18.2},{-1,-1},{70,20}}} end
local modules={ZoneDB={GetUiMapIdByAreaId=function(_,id) return id+100 end,IsDungeonZone=function(id) return id==2 end},
  QuestieDB={GetItemDroprate=function(_,id) return {farmNPCs[id].rate,'wowhead'} end}}
QuestieLoader={ImportModule=function(_,name) return modules[name] end}
C_Map={GetMapInfo=function(id) return {name=id==101 and 'Test Forest' or 'Test Dungeon',mapType=id==101 and 3 or 4} end}
local provider=F.FarmProviders()
local fs=F.FarmSources(200,provider)
eq(#fs,2,'elite, friendly, instance and explicit zero rates excluded')
eq(fs[1].id,2,'sources ordered by known reference rate')
eq(fs[2].places[1].coords,'42.5, 18.2 / 70.0, 20.0','valid zone coordinates retained')
farmItems[201]={6,8}
fs=F.FarmSources(201,provider)
eq(fs[1].rate,nil,'invalid rate is unknown, never clamped into certainty')
farmItems[201]={6}
F.db.recipes[50]={observedBuild=F.Build(),reagents={{itemID=201},{itemID=1000},{itemID=1001},{itemID=999}}}
prices[200]=100; ages[200]=0; prices[201]=1000; ages[201]=0
prices[2770]=500; ages[2770]=0
prices[1000]=5000; ages[1000]=0; prices[1001]=5000; ages[1001]=0
F.db.cut=5; F.farmAllLevels=false; F.farmLevel=nil
local farms,err,stats=F.FarmResults()
eq(err,nil,'compatible providers accepted')
eq(#farms,2,'unloaded, bound, quest-class and unknown-level sources excluded')
eq(farms[1].id,200,'known rates precede unranked higher-price item')
eq(farms[1].level,10,'recommendation minimum matches selected lower-level mob')
eq(farms[1].score,2375,'one-item drop model after cut per 100 kills')
eq(farms[2].score,nil,'missing percentage never invents expected value')
eq(stats.loading,1,'uncached item reported for retry')
eq(stats.above,1,'gathering level unknown until all-level mode')
F.farmAllLevels=true; farms=F.FarmResults()
eq(#farms,3,'all levels exposes gathering objects for research')
eq(farms[1].level,30,'all-level mode uses higher rate source and its own minimum')
eq(farms[1].score,7600,'higher source reference rate applied')
eq(farms[3].level,nil,'object level not fabricated from item equip level')
F.farmAllLevels=false; F.farmLevel=9; eq(#F.FarmResults(),0,'simulated lower level excludes unreachable mobs')
F.farmLevel=20
ages[201]=2; farms=F.FarmResults(); eq(#farms,1,'stale scalar prices excluded from farming')
ages[201]=0
F.RefreshFarms(); F.farmRows[1].scripts.OnClick()
eq(F.report:IsShown(),true,'clicking farm item opens details')
eq(F.reportText.text:find('25.00%%')~=nil,true,'details include per-source percentage')
eq(F.reportText.text:find('Test Forest',1,true)~=nil,true,'details include location')
eq(F.reportText.text:find('NOT measured Forever rates',1,true)~=nil,true,'reference provenance visible')
F.ShowTab('crafting'); eq(F.farmPanel:IsShown(),false,'crafting tab hides farms')
eq(F.craftPanel:IsShown(),true,'crafting restored')
SlashCmdList.MOBAUCTION('farms'); eq(F.activeTab,'farms','farms command selects tab')
SlashCmdList.MOBAUCTION('learn'); eq(F.activeTab,'crafting','learn command returns to crafting')
AuctionHouseFrame:Hide(); F.ahOpen=false; searchTerms=nil; F.ScanFarms(); eq(searchTerms,nil,'farm scan requires open AH')
AuctionHouseFrame:Show(); F.ahOpen=true; F.ScanFarms(); eq(searchTerms,nil,'uncached farm name defers scan')
farmItems[999]=nil; F.ScanFarms(); eq(#searchTerms,2,'farm scan includes mapped saleable items needing fresh prices')
local oldRate=modules.QuestieDB.GetItemDroprate
modules.QuestieDB.GetItemDroprate=function() error('not ready') end
farms=F.FarmResults(); eq(farms[1].score,nil,'not-ready rate provider safely becomes unknown')
modules.QuestieDB.GetItemDroprate=oldRate
LibQuestieDB.RequireContract=function() return false end
farms,err=F.FarmResults(); eq(#farms,0,'incompatible provider disables farming only')
eq(type(err),'string','provider error has actionable message')
F.ShowTab('crafting')
-- Report windows must not blend with the opportunity page, including reopening
-- through slash commands and closing with Back/Escape (both call Hide).
F.Open(); F.ShowCatalogue()
eq(F.window:IsShown(),false,'catalogue hides underlying opportunity page')
eq(F.details:IsShown(),false,'catalogue hides recipe inspector')
eq(F.report.strata,'DIALOG','catalogue uses dialog strata')
F.report:Hide(); eq(F.window:IsShown(),true,'closing catalogue returns to opportunity page')
F.reportScroll:SetVerticalScroll(300); F.ShowCatalogue()
eq(F.reportScroll.scroll,0,'new report resets old scroll position')
F.Open(); eq(F.report:IsShown(),false,'launcher dismisses existing catalogue')
eq(F.window:IsShown(),true,'launcher brings main page forward')

-- Forever Skills pane discovery with no retail profession globals. A collapsed
-- header must not make a previously observed profession look unlearned.
local oldGetProfessions,oldGetProfessionInfo=GetProfessions,GetProfessionInfo
GetProfessions=nil; GetProfessionInfo=nil
local skillRows={{name='Professions',isHeader=true,isCollapsed=false},
  {name='Cooking',skillID=185,rank=225},{name='Blacksmithing',skillID=164,rank=200},
  {name='Defense',skillID=95,rank=180}}
C_SkillInfo={GetNumSkillLines=function() return #skillRows end,GetSkillLineInfo=function(i) return skillRows[i] end}
found=F.DiscoverProfessions()
eq(found[185],225,'Forever skillID and rank detect Cooking')
eq(found[164],200,'Forever skillID and rank detect Blacksmithing')
eq(found[95],nil,'combat skill not mistaken for profession')
eq(F.currentProfessionsComplete,true,'expanded skill list provides complete census')
skillRows[1].isCollapsed=true; skillRows[2]=nil; skillRows[3]=nil; skillRows[4]=nil
F.DiscoverProfessions(); eq(F.currentProfessionsComplete,false,'collapsed skill headers are not authoritative')
eq(F.currentProfessions[185],225,'partial census preserves observed profession')
C_SkillInfo=nil
function GetNumSkillLines() return 2 end
function GetSkillLineInfo(i) if i==1 then return 'Professions',true,true,0 else return 'Cooking',false,false,226 end end
found=F.DiscoverProfessions(); eq(found[185],226,'legacy global skill detection')
GetNumSkillLines=nil; GetSkillLineInfo=nil

-- Known recipes from the legacy trade-skill UI must import and scan even when
-- the C_TradeSkillUI namespace is absent or present but empty.
local modern=C_TradeSkillUI; C_TradeSkillUI=nil
TradeSkillFrame=widget(); TradeSkillFrame:Show()
local legacyRank=225
function GetTradeSkillLine() return 'Cooking',legacyRank,300 end
local legacyRows={{name='Food',kind='header'},
  {name='Legacy steak',kind='optimal',spell=8001,output=100},
  {name='Legacy soup',kind='trivial',output=101}}
function GetNumTradeSkills() return #legacyRows end
function GetTradeSkillInfo(i) return legacyRows[i].name,legacyRows[i].kind end
function GetTradeSkillItemLink(i) return '|Hitem:'..legacyRows[i].output..':0|h[Food]|h' end
function GetTradeSkillRecipeLink(i) return legacyRows[i].spell and ('|Henchant:'..legacyRows[i].spell..'|h[Recipe]|h') end
function GetTradeSkillNumMade() return 2,4 end
function GetTradeSkillNumReagents() return 2 end
local reagentReady=true
function GetTradeSkillReagentInfo(_,j) return 'Reagent',nil,j==1 and 3 or 1,0 end
function GetTradeSkillReagentItemLink(_,j) if reagentReady then return '|Hitem:'..(j==1 and 200 or 201)..'|h[Reagent]|h' end end
F.db.recipes={}; F.db.requirements={}; F.db.verifiedRequirements={}
F.db.selectedProfessions={[185]=true}; F.db.skills[185]=nil; F.filter=nil
eq(F.ReadRecipes(),2,'legacy reader skips headers and imports learned rows')
eq(F.db.recipes[8001].learned,true,'visible legacy recipe known without learned boolean')
eq(F.db.recipes[8001].made,2,'legacy import uses minimum yield')
eq(F.db.recipes[8001].reagents[1].qty,3,'legacy quantities come from client')
eq(F.db.recipes[8001].observedSkill,225,'open profession supplies skill evidence')
eq(F.Eligible(F.db.recipes[8001]),true,'known legacy recipe eligible without trainer visit')
local synthetic=F.db.legacyRecipeKeys['185:101:Legacy soup']
eq(synthetic<0,true,'missing spell link gets persistent local ID')
F.ReadRecipes(); eq(F.db.legacyRecipeKeys['185:101:Legacy soup'],synthetic,'local recipe ID stable across imports')
local temp=legacyRows[2]; legacyRows[2]=legacyRows[3]; legacyRows[3]=temp
F.ReadRecipes(); eq(F.db.recipes[8001].name,'Legacy steak','row reorder does not change recipe identity')
legacyRows[2].spell=8002; F.ReadRecipes()
eq(F.db.recipes[synthetic],nil,'later spell link replaces temporary local identity')
eq(F.db.recipes[8002].name,'Legacy soup','real spell identity adopted')
F.ahOpen=true; searchTerms=nil; F.ScanCraftPrices()
eq(#searchTerms,4,'imported legacy outputs and reagents reach Auctionator')
F.SaveSetup({[185]=true},{[185]='225'})
eq(F.db.skills[185],nil,'saving detected skill keeps auto mode')
legacyRank=230; fire('TRADE_SKILL_LIST_UPDATE')
eq(F.SkillLevel(185),230,'observed skill follows gains')
eq(F.db.recipes[8001].observedSkill,225,'earlier known-at rank remains valid evidence')
F.SetSkill(185,'200'); eq(F.ScanEligible(F.db.recipes[8001]),false,'manual lower-level preview remains respected')
eq(F.ScanStatus():find('above your selected skill',1,true)~=nil,true,'scan explains skill filter instead of generic error')
F.SetSkill(185,'auto')
reagentReady=false; F.ReadRecipes()
eq(F.ScanEligible(F.db.recipes[8001]),false,'partial reagents cannot give incomplete scan or cost')
reagentReady=true; fire('GET_ITEM_INFO_RECEIVED',200,true)
eq(F.Eligible(F.db.recipes[8001]),true,'item cache event repairs partial legacy import')
C_TradeSkillUI={GetBaseProfessionInfo=function() return nil end}
F.db.recipes={}; eq(F.ReadRecipes(),2,'empty modern namespace falls back to legacy window')
function IsTradeSkillLinked() return true end
F.db.recipes={}; eq(F.ReadRecipes(),0,'linked profession never imports as player known recipes')
IsTradeSkillLinked=nil
TradeSkillFrame:Hide(); searchTerms=nil
F.ScanCraftPrices(); eq(searchTerms,nil,'empty import never launches empty AH search')
eq(messages[#messages]:find('No recipes imported yet',1,true)~=nil,true,'empty scan reports import step')
TradeSkillFrame:Show(); fire('TRADE_SKILL_SHOW')
eq(F.db.recipes[8001]~=nil,true,'opening legacy profession populates catalogue automatically')
TradeSkillFrame:Hide()

-- Enchanting's older Craft window uses a different result tuple and must not
-- turn a non-item enchant service into an auctionable item.
CraftFrame=widget(); CraftFrame:Show()
function GetCraftDisplaySkillLine() return 'Enchanting',100,150 end
function GetNumCrafts() return 2 end
function GetCraftInfo(i) return i==1 and 'Enchantments' or 'Enchant bracer',nil,i==1 and 'header' or 'optimal' end
function GetCraftItemLink() return '|Henchant:9001|h[Enchant bracer]|h' end
function GetCraftNumReagents() return 1 end
function GetCraftReagentInfo() return 'Dust',nil,2 end
function GetCraftReagentItemLink() return '|Hitem:200|h[Dust]|h' end
fire('CRAFT_SHOW')
eq(F.db.recipes[9001].profession,333,'legacy Craft event imports correct profession')
eq(F.db.recipes[9001].problem,'No auctionable item output','non-item enchant service explained')
CraftFrame:Hide()
C_TradeSkillUI=modern; GetProfessions=oldGetProfessions; GetProfessionInfo=oldGetProfessionInfo
-- End-to-end audit of the Forever-shaped APIs, without retail profession APIs.
MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,}; F.Init(); F.worthLearning=false; F.filter=nil
GetProfessions=nil; GetProfessionInfo=nil; C_TradeSkillUI=nil
C_SkillInfo={GetSkillLineInfoByID=function(id)
  if id==185 then return {skillID=185,name='Cooking',rank=230,isHeader=false} end
end}
found=F.DiscoverProfessions()
eq(found[185],230,'direct Forever skill lookup works with collapsed pane')
eq(F.currentProfessionsComplete,true,'by-ID discovery supplies profession census')
F.SaveSetup({[185]=true},{[185]='230'})
legacyRank=230; TradeSkillFrame:Show(); fire('TRADE_SKILL_SHOW')
TradeSkillFrame:Hide(); F.ahOpen=true
prices[100]=1000; ages[100]=0; prices[200]=20; ages[200]=0; prices[201]=30; ages[201]=0
searchTerms=nil; F.ScanCraftPrices(); eq(#searchTerms,4,'fresh setup to legacy import to scan succeeds')

-- Vendor information has separate purchasable, usable and extended-cost fields.
local merchantRows={
  {name='Spice',price=100,stackCount=5,numAvailable=-1,isPurchasable=true,isUsable=true,hasExtendedCost=false},
  {name='Token reagent',price=1,stackCount=1,numAvailable=-1,isPurchasable=true,isUsable=true,hasExtendedCost=true},
  {name='Limited reagent',price=1,stackCount=1,numAvailable=2,isPurchasable=true,isUsable=true,hasExtendedCost=false},
  {name='Unavailable reagent',price=1,stackCount=1,numAvailable=-1,isPurchasable=false,isUsable=true,hasExtendedCost=false},
}
function GetMerchantNumItems() return #merchantRows end
function GetMerchantItemID(i) return 199+i end
function GetMerchantItemLink(i) return '|Hitem:'..(199+i)..'|h[Supplier item]|h' end
C_MerchantFrame={GetItemInfo=function(i) return merchantRows[i] end}
GetMerchantItemInfo=nil; fire('MERCHANT_SHOW')
eq(F.db.vendors[200].price,100,'modern merchant gold price retained')
eq(F.db.vendors[200].bundle,5,'modern merchant bundle retained')
eq(F.db.vendors[201],nil,'extended-cost vendor item not treated as gold-only')
eq(F.db.vendors[202],nil,'limited stock not treated as unlimited supplier')
eq(F.db.vendors[203],nil,'unpurchasable supplier item excluded')
C_MerchantFrame=nil
function GetMerchantItemInfo(i)
  local v=merchantRows[i]
  return v.name,nil,v.price,v.stackCount,v.numAvailable,v.isPurchasable,v.isUsable,v.hasExtendedCost
end
F.db.vendors={}; fire('MERCHANT_SHOW')
eq(F.db.vendors[200].price,100,'legacy merchant tuple reads usable separately from extended cost')
eq(F.db.vendors[201],nil,'legacy extended-cost item excluded')

-- Settings validate atomically and affect both checked costs and fee forecasts.
eq(F.SavePricingSettings({cut='15',duration='4',failures='2',maxAge='1'}),false,'invalid settings rejected')
eq(F.db.cut,5,'failed settings save has no partial writes')
eq(F.SavePricingSettings({cut='15',duration='1',failures='2',maxAge='1'}),true,'pricing settings accepted')
commodity[200]={{unitPrice=20,quantity=100}}; full[200]=true
items[201]={{auctionID=401,buyoutAmount=30,quantity=1},{auctionID=402,buyoutAmount=60,quantity=2}}; full[201]=true
fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
F.RequestDepth(201); fire('ITEM_SEARCH_RESULTS_UPDATED',C_AuctionHouse.MakeItemKey(201))
F.priceCache={}
local flow=F.Evaluate(F.db.recipes[8001],F.db,F.Quote,F.Deposit)
eq(flow.cost,90,'full workflow material cost with vendor comparison')
eq(flow.value,2000,'minimum yield sale forecast')
eq(flow.fee,300,'user-configured auction fee applied')
eq(flow.deposit,4,'game deposit quote used')
eq(flow.adjusted,1602,'full workflow after two failed-listing losses')
eq(flow.materialsComplete,true,'material evidence complete')
eq(flow.needsDeposit,false,'known deposit identified')
F.Open(); F.ShowDetails(F.db.recipes[8001])
eq(F.window:IsShown(),false,'batch check hides main page')
F.details:Hide(); eq(F.window:IsShown(),true,'closing batch check restores main page')
F.ShowCatalogue(); F.reportRows[1].scripts.OnClick(F.reportRows[1])
eq(F.details:IsShown(),true,'clickable catalogue opens recipe inspector')
eq(F.report:IsShown(),false,'catalogue hidden during inspection')
F.details:Hide(); eq(F.report:IsShown(),true,'inspector returns to catalogue')
F.report:Hide(); eq(F.window:IsShown(),true,'catalogue returns to main after inspecting recipe')
F.ShowSettings(); eq(F.window:IsShown(),false,'settings hides main page')
F.settings:Hide(); eq(F.window:IsShown(),true,'settings Back restores main page')
F.ShowSetup(); eq(F.window:IsShown(),false,'setup hides main page')
F.setup:Hide(); eq(F.window:IsShown(),true,'closing setup returns to main page')
SlashCmdList.MOBAUCTION('help')
eq(F.reportText.text:find('MobAuction '..F.VERSION,1,true)~=nil,true,'help identifies installed build')
eq(F.LearningStatus():find('No unlearned recipes',1,true)~=nil,true,'learning feature explains legacy catalogue limit')

-- Refresh must not reuse a stale sale-price cache, and deposit absence must
-- remain separate from material pricing.
F.Open(); F.ShowDetails(F.db.recipes[8001]); prices[100]=2000
F.RefreshDetails()
eq(F.detailSummary.text:find(F.Money(3310),1,true)~=nil,true,'Refresh costs uses new output quote')
flow=F.Evaluate(F.db.recipes[8001],F.db,F.Quote,function() return nil,'Need output in bags' end)
eq(flow.materialsComplete,true,'missing deposit preserves known material cost')
eq(flow.adjusted,nil,'no fabricated net profit without deposit')
eq(flow.needsDeposit,true,'missing deposit has specific UI state')
prices[100]=nil; F.priceCache={}
flow=F.Evaluate(F.db.recipes[8001],F.db,F.Quote,F.Deposit)
eq(flow.materialsComplete,true,'missing output price preserves material cost')
eq(flow.profit,nil,'missing output price does not invent profit')
prices[100]=1000

-- A partial book older than a minute needs a new search, not pagination of a
-- discarded query; a failed search should not leave a permanent pending book.
F.depth[200]={seen=now-61,complete=false,kind='commodity',lots={}}
local oldRequests,oldMore=requests,moreRequests
F.RequestDepth(200)
eq(requests,oldRequests+1,'expired partial book starts a fresh search')
eq(moreRequests,oldMore,'expired book does not request stale pages')
local sendSearch=C_AuctionHouse.SendSearchQuery
C_AuctionHouse.SendSearchQuery=function() error('busy') end
F.RequestDepth(200); eq(F.depth[200],nil,'failed request clears pending state')
C_AuctionHouse.SendSearchQuery=sendSearch

-- Muting notifications does not freeze the visible deal list or promote own listings.
ledger[900].updated=now; ledger[900].median7d=10000; F.db.dealAlerts=false
local messageCount=#messages
browse={{itemKey={itemID=900},minPrice=5000}}
fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
eq(#F.DealList(),1,'muted alerts still collect current recipe bargains')
eq(#messages,messageCount,'muted alerts do not chat')
browse[1].minPrice=9900; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
eq(#F.DealList(),0,'muted alerts still remove ceased bargains')
browse[1].minPrice=5000; browse[1].containsOwnerItem=true; fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
eq(#F.DealList(),0,'own browse minimum is not a buyable bargain')
-- A large catalogue stays navigable and unrelated reports hide its paging controls.
F.db.recipes={}
for i=1,25 do F.db.recipes[i]={id=i,profession=185,name=string.format('Recipe %02d',i),learned=true,
  observedBuild=F.Build(),observedSkill=230,output=100,made=1,reagents={{itemID=200,qty=1}}} end
F.Open(); F.ShowCatalogue()
eq(#F.reportRows,20,'catalogue creates at most twenty recipe rows per page')
F.reportNext.scripts.OnClick(); eq(F.reportData.page,2,'catalogue Next changes page')
eq(F.reportRows[1].text.text:find('Recipe 21',1,true)~=nil,true,'second page shows correct recipe')
eq(F.reportRows[6]:IsShown(),false,'unused second-page rows hidden')
F.ShowHelp(); eq(F.reportNext:IsShown(),false,'help hides recipe pagination')
F.Open(); F.ShowSettings()
F.settingFields.cut:SetText('10'); F.settingFields.duration:SetText('9')
local saveSettings
for _,frame in ipairs(frames) do if frame.text=='Save settings' then saveSettings=frame end end
saveSettings.scripts.OnClick()
eq(F.settings:IsShown(),true,'invalid UI settings keep editor open')
eq(F.db.cut,15,'invalid UI settings do not partially change auction fee')
F.settingFields.duration:SetText('2'); saveSettings.scripts.OnClick()
eq(F.db.cut,10,'settings button persists edited fee')
eq(F.db.duration,2,'settings button persists selected duration')
eq(F.window:IsShown(),true,'saving settings returns to main')

-- Large whole-stack sweeps are explicitly bounded and never called a global optimum.
local lots={}; for i=1,500 do lots[i]={price=10+i,quantity=1+(i%10)} end
F.ahOpen=true; F.depth[201]={complete=true,kind='item',seen=now,lots=lots}
F.db.cut=5; F.db.duration=1; F.db.failures=1; F.db.strictCosts=true; F.db.vendors={}
prices[100]=100000; ages[100]=0
local planRecipe={id=1,name='Large batch',output=100,made=1,reagents={{itemID=201,qty=10}}}
local best,compared,limited=F.PlanBatch(planRecipe)
eq(limited,true,'whole-stack planner enforces shared work budget')
eq(compared>0 and compared<100,true,'planner reports actual compared batch count')
eq(best~=nil,true,'planner preserves best fully evaluated batch')
eq(F.planningWork,nil,'planner leaves ordinary pricing unbudgeted')
eq(F.DepthCost({complete=true,kind='commodity',lots={}},1),nil,'empty commodity book cannot supply item')
eq(F.DepthCost({complete=true,kind='commodity',lots={{price=10,quantity=2},{price=50,quantity=3}}},5),170,'prefix pricing includes exact last-tier boundary')
assert(loadfile('tests/import_regression.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/terminology.lua'))()(F,eq)
assert(loadfile('tests/import_readiness.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/auction_state.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/profit_order.lua'))()(F,eq)
assert(loadfile('tests/auto_import.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/deposit.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/learning_integration.lua'))()(F,eq)
assert(loadfile('tests/auction_learning.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/scan_workflow.lua'))()(F,eq,widget)
assert(loadfile('tests/full_scan.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/catalogue.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/full_scan_integration.lua'))()(F,eq,fire,widget)
assert(loadfile('tests/reference_integration.lua'))()(F,eq,fire,widget)
print('PASS final: '..count..' checks')

