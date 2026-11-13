local _, F = ...
function F.Build()
  if GetBuildInfo then local _, build = GetBuildInfo(); return tostring(build) end
  return 'unknown'
end
function F.ReadTrainer()
  if not GetNumTrainerServices or not GetTrainerServiceSkillReq or not C_TooltipInfo or not C_TooltipInfo.GetTrainerService then return end
  for index = 1, GetNumTrainerServices() do
    local data = F.Safe(C_TooltipInfo.GetTrainerService, index)
    local id = data and data.id
    local recipe = id and F.db.recipes[id]
    local serviceName = GetTrainerServiceInfo and F.Safe(GetTrainerServiceInfo, index)
    if recipe and serviceName == recipe.name and recipe.observedBuild == F.Build() then
      local ok, skillName, rank = pcall(GetTrainerServiceSkillReq, index)
      local name = F.db.professionNames[recipe.profession]
      if ok and skillName == name and type(rank) == 'number' and rank >= 0 then
        F.db.verifiedRequirements[id] = { rank = rank, build = F.Build(), profession = recipe.profession,
          output = recipe.output, source = UnitName('npc') or 'Trainer', seen = time() }
        -- Available is the client's assessment of all training requirements, not just rank.
        local _, category = GetTrainerServiceInfo(index)
        recipe.trainerAvailable = category == 'available'
        recipe.trainerSeen = time()
        recipe.trainerName = UnitName('npc') or 'Trainer'
        recipe.trainingCost = nil
        if GetTrainerServiceCost then
          local costOK, cost, talentCost, professionCost = pcall(GetTrainerServiceCost, index)
          if costOK and type(cost) == 'number' and (talentCost or 0) == 0 and (professionCost or 0) == 0 then recipe.trainingCost = cost end
        end
      end
    end
  end
end
function F.Coverage()
  local counts = { known = 0, unlearned = 0, verified = 0, fallback = 0, unknown = 0 }
  for _, recipe in pairs(F.db.recipes) do
    if F.db.selectedProfessions[recipe.profession] and (not F.filter or recipe.profession == F.filter) then
      local state = recipe.learned == false and 'unlearned' or 'known'
      counts[state] = counts[state] + 1
      local _, _, kind = F.RequiredSkill(recipe)
      if kind == 'verified' or kind == 'manual' then counts.verified = counts.verified + 1
      elseif kind == 'fallback' then counts.fallback = counts.fallback + 1
      else counts.unknown = counts.unknown + 1 end
    end
  end
  return counts
end
function F.LearningStatus()
  local c=F.Coverage()
  local auction=F.AuctionLearningStatus and F.AuctionLearningStatus() or ''
  local intro=c.unlearned==0 and 'No unlearned recipes imported from your profession window yet. ' or ''
  local catalogue=F.CatalogueStatusText and F.CatalogueStatusText() or ''
  return intro..'Use Full AH scan at the auction house to price materials, crafted items and recipe items together. Learning: all sources includes catalogue research; Learning: AH recipes shows listed recipe items. Learn price is separate from crafting profit.\n'..auction..'\n'..catalogue
end
function F.ReportCoverage()
  local c = F.Coverage()
  F.Say(string.format('Client catalogue: %d known, %d unlearned; skill requirements: %d verified/manual, %d Classic fallback, %d unknown.', c.known,c.unlearned,c.verified,c.fallback,c.unknown))
  for _, r in pairs(F.db.recipes) do
    if not F.filter or r.profession == F.filter then
      local rank, source = F.RequiredSkill(r)
      F.Say(string.format('%d %s | %s | skill %s (%s)', r.id, r.name, r.learned == false and 'Unlearned' or 'Known', rank or '?', source))
    end
  end
end
local frame = CreateFrame('Frame')
frame:RegisterEvent('TRAINER_SHOW'); frame:RegisterEvent('TRAINER_UPDATE')
frame:SetScript('OnEvent', function() if F.db then F.ReadTrainer() end end)

function F.WorthLearning()
  local rows = {}
  local selected={}
  for profession,enabled in pairs(F.db.selectedProfessions or {}) do
    if enabled and (not F.filter or F.filter==profession) then selected[profession]=true end
  end
  -- Build one profession-scoped reference view and share it between AH offers
  -- and catalogue sources. The full registry may contain thousands of entries.
  local catalogue=F.CatalogueRecipes and F.CatalogueRecipes(selected) or nil
  local old = F.db.includeUnlearned
  F.db.includeUnlearned = true
  F.priceCache = {}
  local settings={}; for key,value in pairs(F.db) do settings[key]=value end
  settings.crafts=1
  for _, recipe in pairs(F.db.recipes) do
    if recipe.learned == false and F.Eligible(recipe) and type(recipe.trainingCost) == 'number' then
      local row = F.Evaluate(recipe, settings, F.Quote, F.Deposit)
      if row.adjusted and row.adjusted > 0 and not row.estimated then
        row.acquisition='trainer'; row.acquisitionPrice=recipe.trainingCost
        row.acquisitionPriceSource='Trainer: '..(recipe.trainerName or '?')
        row.canLearn=true; row.status='Trainer'; row.pending={}
        rows[#rows+1] = row
      end
    end
  end
  F.db.includeUnlearned = old
  if F.AuctionLearningRows then
    for _,row in ipairs(F.AuctionLearningRows(catalogue)) do rows[#rows+1]=row end
  end
  if F.learningOnlyAH then
    local listed={}; for _,row in ipairs(rows) do if row.acquisition=='auction' then listed[#listed+1]=row end end
    rows=listed
  elseif F.CatalogueLearningRows then
    local seen={}; for _,row in ipairs(rows) do seen[row.recipe.id]=true end
    for _,row in ipairs(F.CatalogueLearningRows(seen,catalogue)) do rows[#rows+1]=row end
  end
  -- Learning prices are information for the player, never a profit deduction
  -- or a ranking factor. Compare the same one-craft quantity for every entry.
  table.sort(rows,function(a,b)
    local ap,bp=a.profit or -math.huge,b.profit or -math.huge
    if ap~=bp then return ap>bp end
    if a.recipe.name~=b.recipe.name then return a.recipe.name<b.recipe.name end
    if a.recipe.id~=b.recipe.id then return a.recipe.id<b.recipe.id end
    return (a.acquisitionItemID or 0)<(b.acquisitionItemID or 0)
  end)
  return rows
end
