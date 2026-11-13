-- Ordering must follow the displayed sale profit, independently of price
-- confidence, refundable deposits, and expected losses on failed listings.
return function(F,eq)
  local oldDB,oldFilter,oldCurrent,oldComplete=F.db,F.filter,F.currentProfessions,F.currentProfessionsComplete
  local oldQuote,oldDeposit=F.Quote,F.Deposit
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[185]=true},detectedSkills={[185]=244}}
  F.Init(); F.filter=185; F.currentProfessions={[185]=244}; F.currentProfessionsComplete=true
  local names={'High estimated','Bravo checked','Missing deposit','Loss','A missing sale','B missing material','Able checked'}
  local values={1000,900,800,100,nil,900,900}
  for id,name in ipairs(names) do
    F.db.recipes[id]={id=id,name=name,profession=185,learned=true,observedBuild=F.Build(),observedSkill=244,
      output=1000+id,made=1,reagents={{itemID=2000+id,qty=1}}}
  end
  F.Quote=function(id,quantity,reagent)
    if reagent then
      return id~=2006 and 100*quantity or nil,'Test materials',nil,{kind=id==2001 and 'estimate' or 'checked'}
    end
    local value=values[id-1000]
    return value and value*quantity,'Test sale'
  end
  F.Deposit=function(id,quantity)
    if id==1003 then return nil,'Loading quote' end
    return (id==1001 and 900 or 0)*quantity,'Test quote'
  end
  local rows=F.Results()
  eq(#rows,7,'all eligible results remain visible')
  eq(rows[1].recipe.id,1,'highest sale profit comes first even with estimated costs')
  eq(rows[1].profit,850,'ranking uses sale revenue less cut and materials')
  eq(rows[1].adjusted,-50,'failed deposits remain visible without changing sale-profit order')
  eq(rows[2].recipe.id,7,'equal sale profit sorts by name')
  eq(rows[3].recipe.id,2,'lower checked profit cannot outrank higher estimated profit')
  eq(rows[4].recipe.id,3,'known sale profit remains ranked while deposit loads')
  eq(rows[4].adjusted,nil,'unknown deposit cannot fabricate adjusted profit')
  eq(rows[5].profit,-5,'known loss sorts after positive profits')
  eq(rows[6].recipe.id,5,'unknown sale follows known profit and loss')
  eq(rows[7].recipe.id,6,'missing material costs cannot look profitable')
  F.db.crafts=2; rows=F.Results()
  eq(rows[1].profit,1700,'ranking recalculates for the configured craft batch')
  F.activeTab='crafting'; F.worthLearning=false; F.Open()
  eq(F.rows[1].result.recipe.id,1,'main interface displays highest sale profit first')
  eq(F.recipeHint.text:find('Highest sale profit first.',1,true)~=nil,true,'interface states its ordering')
  F.Quote=oldQuote; F.Deposit=oldDeposit
  F.db=oldDB; MobAuctionDB=oldDB; F.filter=oldFilter; F.currentProfessions=oldCurrent; F.currentProfessionsComplete=oldComplete
end
