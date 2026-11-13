-- Exercise the real import event path while advancing only the game's timers.
-- ReadRecipes/Refresh are never invoked by the simulated player in these cases.
return function(F,eq,fire,widget)
  local oldTimer,oldAPI=C_Timer,C_TradeSkillUI
  local oldWindow,oldRefresh,oldReader=F.window,F.Refresh,F.ReadRecipes
  local oldProfessions,oldProfessionInfo=GetProfessions,GetProfessionInfo
  local oldProfessionFrame,oldTradeFrame,oldCraftFrame=ProfessionsFrame,TradeSkillFrame,CraftFrame
  local oldSkillInfo=C_SkillInfo
  local queue,clock,callbacks={},0,0
  local function enqueue(delay,fn)
    local timer={at=clock+delay,fn=fn,cancelled=false}
    function timer:Cancel() self.cancelled=true end
    queue[#queue+1]=timer
    return timer
  end
  C_Timer={NewTimer=enqueue,After=function(delay,fn) enqueue(delay,fn) end}
  local function pending()
    local count=0
    for _,timer in ipairs(queue) do if not timer.cancelled then count=count+1 end end
    return count
  end
  local function tick()
    local index,nextTimer
    for i,timer in ipairs(queue) do
      if not timer.cancelled and (not nextTimer or timer.at<nextTimer.at) then index,nextTimer=i,timer end
    end
    if not index then queue={}; return false end
    table.remove(queue,index); clock=nextTimer.at; callbacks=callbacks+1
    assert(callbacks<200,'automatic import must never leave an unbounded timer loop')
    nextTimer.fn()
    return true
  end
  local function finish() while tick() do end end
  local reads,refreshes=0,0
  F.ReadRecipes=function(...) reads=reads+1; return oldReader(...) end
  F.window=widget(); F.Refresh=function() refreshes=refreshes+1 end
  TradeSkillFrame=nil; CraftFrame=nil; ProfessionsFrame=widget(); ProfessionsFrame:Hide()
  C_SkillInfo=nil
  local ranks={[164]=190,[185]=244}
  GetProfessions=function() return 1,2 end
  GetProfessionInfo=function(index)
    local id=index==1 and 164 or 185
    return F.professions[id],nil,ranks[id],300,nil,nil,id
  end
  local selected,sourceCounter,ready,changing=164,1,false,false
  local missingSchematic,linked
  local rows={
    [2660]={name='Rough Sharpening Stone',learned=true,profession=164,output=2862,reagent=2835},
    [2661]={name='Copper Chain Belt',learned=true,profession=164,output=2851,reagent=2840},
    [2538]={name='Charred Wolf Meat',learned=true,profession=185,output=2679,reagent=2672},
  }
  local function info(id)
    return {professionID=id,professionName=F.professions[id],skillLevel=ranks[id],sourceCounter=sourceCounter}
  end
  C_TradeSkillUI={
    IsTradeSkillReady=function() return ready end,
    IsDataSourceChanging=function() return changing end,
    IsTradeSkillLinked=function() return linked end,
    GetChildProfessionInfo=function() return info(selected) end,
    GetBaseProfessionInfo=function() return info(selected) end,
    GetAllRecipeIDs=function() return selected==164 and {2660,2661} or {2538} end,
    GetProfessionInfoByRecipeID=function(id) return info(rows[id].profession) end,
    GetRecipeInfo=function(id) return rows[id] end,
    GetRecipeSchematic=function(id)
      if missingSchematic==id then return nil end
      local row=rows[id]
      return {outputItemID=row.output,quantityMin=1,reagentSlotSchematics={
        {reagentType=0,quantityRequired=1,reagents={{itemID=row.reagent}}},
      }}
    end,
  }
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[164]=true,[185]=true}}
  F.Init(); F.filter=nil; F.worthLearning=false
  fire('TRADE_SKILL_CLOSE')
  local function open()
    ProfessionsFrame:Show(); fire('TRADE_SKILL_SHOW')
  end
  local function close()
    ProfessionsFrame:Hide(); fire('TRADE_SKILL_CLOSE')
  end

  -- Opening can precede API readiness; no subsequent Blizzard event is needed.
  open()
  eq(F.db.lastImportAttempt.reason,'not_ready','opening a loading profession records its initial state')
  eq(next(F.db.recipes),nil,'loading profession does not create guessed plans')
  eq(pending(),1,'opening queues one delayed import')
  local beforeRefresh=refreshes
  ready=true; finish()
  eq(F.db.recipes[2660].profession,164,'readiness alone lets the delayed import detect known plans')
  eq(F.db.recipes[2661].learned,true,'delayed import records the second learned plan')
  eq(F.db.recipes[2661].observedSkill,190,'automatic import observes the correct Blacksmithing skill')
  eq(F.db.lastImportAttempt.reason,'imported','automatic success replaces the loading diagnosis')
  eq(refreshes>beforeRefresh,true,'delayed import refreshes the visible opportunities window')
  eq(pending(),0,'successful import stops polling')

  -- A loaded row appears now; an unfinished schematic arrives without an event.
  close(); F.db.recipes={}; missingSchematic=2661; open()
  eq(F.db.recipes[2660].learned,true,'opening imports ready plans immediately')
  eq(F.db.recipes[2661],nil,'partial automatic import leaves the loading plan pending')
  eq(F.db.lastImportAttempt.reason,'partial','partial automatic import preserves its loading status')
  missingSchematic=nil; finish()
  eq(F.db.recipes[2661].output,2851,'retry imports the later schematic without a refresh command')
  eq(F.db.lastImportAttempt.reason,'imported','completing a partial import clears pending status')

  -- Closing must make an already queued callback harmless, even if data is ready.
  close(); F.db.recipes={}; ready=false; open()
  local attempt=F.db.lastImportAttempt
  local beforeReads=reads
  close(); ready=true; finish()
  eq(reads,beforeReads,'closing cancels pending reader calls')
  eq(F.db.lastImportAttempt,attempt,'closed callbacks cannot replace the last active diagnostic')
  eq(next(F.db.recipes),nil,'closed callbacks cannot import a retained game recipe list')

  -- Switching cancels the old source's work and imports the current profession.
  selected=185; ready=false; open()
  changing=true; fire('TRADE_SKILL_DATA_SOURCE_CHANGING')
  selected=164; sourceCounter=sourceCounter+1; changing=false; ready=true
  fire('TRADE_SKILL_DATA_SOURCE_CHANGED'); finish()
  eq(F.db.recipes[2660].profession,164,'a queued Cooking retry cannot relabel the new Blacksmithing source')
  eq(F.db.recipes[2538],nil,'a source switch does not invent an import of the earlier loading profession')
  changing=true; fire('TRADE_SKILL_DATA_SOURCE_CHANGING')
  selected=185; sourceCounter=sourceCounter+1; changing=false
  fire('TRADE_SKILL_DATA_SOURCE_CHANGED'); finish()
  eq(F.db.recipes[2538].profession,185,'switching to ready Cooking imports its known recipes automatically')
  eq(F.db.recipes[2538].observedSkill,244,'Cooking automatic import uses Cooking skill')
  eq(F.db.recipes[2661].profession,164,'switching leaves previously imported plans intact')

  -- Item-cache/list bursts cannot schedule one expensive catalogue walk each.
  close(); F.db.recipes={}; selected=164; ready=false; open()
  beforeReads=reads
  for _=1,30 do
    fire('TRADE_SKILL_LIST_UPDATE'); fire('TRADE_SKILL_DETAILS_UPDATE'); fire('GET_ITEM_INFO_RECEIVED',2840,true)
  end
  eq(pending(),1,'list/detail/item event bursts share one delayed import')
  eq(reads-beforeReads<5,true,'event bursts do not repeatedly walk the whole catalogue')
  local beforeCallbacks=callbacks
  finish()
  eq(callbacks-beforeCallbacks<20,true,'persistent unready data has a bounded retry budget')
  eq(pending(),0,'persistent unready data eventually stops polling')
  eq(next(F.db.recipes),nil,'bounded retries never fabricate unavailable plans')
  ready=true; fire('TRADE_SKILL_LIST_UPDATE'); finish()
  eq(F.db.recipes[2660].learned,true,'a later real data event can recover after the retry budget ends')

  -- The After-only timer API cannot cancel handles, so closed callbacks must
  -- still be ignored. This checks cancellation semantics, not timer internals.
  close(); F.db.recipes={}; ready=false
  C_Timer={After=function(delay,fn) enqueue(delay,fn) end}
  open(); beforeReads=reads; close(); ready=true; finish()
  eq(reads,beforeReads,'After-only timer callbacks are invalidated when the profession closes')
  eq(next(F.db.recipes),nil,'After-only callbacks cannot import a closed source')

  -- Viewing another character's linked book must not grant learned recipes.
  C_Timer={NewTimer=enqueue,After=function(delay,fn) enqueue(delay,fn) end}
  linked=true; open(); finish()
  eq(next(F.db.recipes),nil,'automatic import rejects linked professions')
  eq(F.db.lastImportAttempt.reason,'external_source','linked automatic import keeps a useful reason')
  eq(pending(),0,'external profession rejection does not poll forever')
  close(); finish()
  C_Timer=oldTimer; C_TradeSkillUI=oldAPI; C_SkillInfo=oldSkillInfo
  GetProfessions=oldProfessions; GetProfessionInfo=oldProfessionInfo
  ProfessionsFrame=oldProfessionFrame; TradeSkillFrame=oldTradeFrame; CraftFrame=oldCraftFrame
  F.window=oldWindow; F.Refresh=oldRefresh; F.ReadRecipes=oldReader
end
