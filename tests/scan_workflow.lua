-- The user's cooking example must produce a visible, sorted scan forecast.
return function(F,eq,widget)
  local saved={}
  for _,key in ipairs({'db','filter','currentProfessions','currentProfessionsComplete','MarketPrice','ItemInfo','depth','ahOpen','worthLearning','activeTab','page'}) do saved[key]={F[key]} end
  local oldDB=MobAuctionDB
  MobAuctionDB={setupComplete=true,selectedProfessions={[185]=true},detectedSkills={[185]=244}}
  F.Init()
  eq(F.db.assumedDeposit,100,'existing characters default to the requested one silver assumption')
  eq(F.db.strictCosts,false,'scan forecasts are enabled on upgrade')
  F.db.strictCosts=true; F.Init(); eq(F.db.strictCosts,true,'subsequent startup preserves the chosen pricing mode')
  F.db.strictCosts=false; F.filter=185; F.currentProfessions={[185]=244}; F.currentProfessionsComplete=true
  F.ItemInfo=function(id) return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,1,0,0,0 end
  F.MarketPrice=function(id) if id==5471 then return 70,'User meat price' elseif id==250065 then return 900,'User sale price' end end
  F.db.vendors[2692]={price=200,bundle=5,seen=time(),name='Spice vendor'}
  F.depth={}
  F.db.recipes[1250142]={id=1250142,name='Savory Stag Sliders',profession=185,learned=true,
    professionVerified=true,observedBuild=F.Build(),observedSkill=244,output=250065,made=1,
    reagents={{itemID=5471,qty=2},{itemID=2692,qty=3}}}
  local rows=F.Results()
  eq(#rows,1,'known sliders are included in Cooking opportunities')
  eq(rows[1].cost,340,'slider cost includes two meat and the whole five-spice supplier bundle')
  eq(rows[1].profit,515,'slider sale profit subtracts actual ingredient purchases and five percent AH cut')
  eq(rows[1].adjusted,415,'slider adjusted profit subtracts one assumed one-silver failed deposit')
  eq(rows[1].estimated,true,'scan-only meat price is labeled as a forecast')
  F.db.vendors[2692]=nil; rows=F.Results()
  eq(rows[1].profit,nil,'unknown spice price cannot fabricate profit')
  F.db.vendors[2692]={price=200,bundle=5,seen=time(),name='Spice vendor'}
  local first=F.db.recipes[1250142]
  for i=1,24 do local copy={}; for k,v in pairs(first) do copy[k]=v end; copy.id=1250200+i; copy.name='Other recipe '..i; F.db.recipes[copy.id]=copy end
  F.activeTab='crafting'; F.worthLearning=false; F.page=1; F.Open()
  F.craftPanel.scripts.OnMouseWheel(F.craftPanel,-1); eq(F.page,2,'mouse wheel scrolls beyond the first ten results')
  F.rows[1].scripts.OnMouseWheel(F.rows[1],-1); eq(F.page,3,'mouse wheel over a recipe also scrolls')
  F.craftPanel.scripts.OnMouseWheel(F.craftPanel,-1); eq(F.page,3,'scrolling stops at the last result page')
  F.craftPanel.scripts.OnMouseWheel(F.craftPanel,1); eq(F.page,2,'scrolling up returns to earlier results')
  F.craftPanel.scripts.OnMouseWheel(F.craftPanel,1); F.craftPanel.scripts.OnMouseWheel(F.craftPanel,1)
  eq(F.page,1,'scrolling stops at the first result page')
  for key,value in pairs(saved) do F[key]=value[1] end
  MobAuctionDB=oldDB
end
