local _, F = ...
MobAuction = F
F.VERSION='0.6.1'
F.defaults = { cut = 5, duration = 1, failures = 1, maxAge = 1, crafts = 1, strictCosts = true, includeUnlearned = false, dealPercent = 40, dealSaving = 1000, dealAlerts = true }
function F.Init()
  MobAuctionDB = MobAuctionDB or {}
  F.db = MobAuctionDB
  if F.db.assumedDeposit==nil then F.db.assumedDeposit=100 end
  -- Upgrade once to the scan-first workflow; later user pricing choices persist.
  if not F.db.scanForecastsEnabled then
    F.db.strictCosts=false; F.db.scanForecastsEnabled=true
  end
  for k, v in pairs(F.defaults) do if F.db[k] == nil then F.db[k] = v end end
  F.db.recipes = F.db.recipes or {}
  F.db.vendors = F.db.vendors or {}
  F.db.deposits = F.db.deposits or {}
  F.db.skills = F.db.skills or {}
  F.db.detectedSkills = F.db.detectedSkills or {}
  F.db.requirements = F.db.requirements or {}
  F.db.verifiedRequirements = F.db.verifiedRequirements or {}
  F.db.professionNames = F.db.professionNames or {}
  F.db.selectedProfessions = F.db.selectedProfessions or {}
  for id, name in pairs(F.db.professionNames) do
    if type(id)=='number' and id>0 and type(name)=='string' and name~='' then F.professions[id] = name
    else
      F.db.professionNames[id]=nil; F.db.skills[id]=nil; F.db.detectedSkills[id]=nil
      F.db.selectedProfessions[id]=nil; F.professions[id]=nil
    end
  end
  -- Older modern imports used mutable global profession context. Require one
  -- fresh observation before trusting their rank, ownership or trainer metadata.
  for _,recipe in pairs(F.db.recipes) do
    if recipe.reader~='legacy' and not recipe.professionVerified then
      recipe.observedBuild=nil; recipe.observedSkill=nil; recipe.importNeedsRefresh=true
      recipe.trainerAvailable=nil; recipe.trainerSeen=nil; recipe.trainerName=nil; recipe.trainingCost=nil
    end
  end
  -- Record the version actually initialized by the client, separately from the
  -- manifest on disk (which can be replaced while an older copy is running).
  F.db.loadedVersion=F.VERSION
end
function F.Say(s) print('|cffedae49MobAuction:|r ' .. s) end
function F.Money(n)
  if n == nil then return '?' end
  local sign = n < 0 and '-' or ''
  n = math.floor(math.abs(n) + 0.5)
  return string.format('%s%dg %ds %dc', sign, math.floor(n / 10000), math.floor(n / 100) % 100, n % 100)
end
function F.SavePricingSettings(values)
  local limits={cut={0,100},duration={1,3},failures={0,100},maxAge={0,30}}
  local parsed={}
  for key,range in pairs(limits) do
    local n=tonumber(values[key])
    if not n or n~=math.floor(n) or n<range[1] or n>range[2] then return false,key..' must be a whole number from '..range[1]..' to '..range[2]..'.' end
    parsed[key]=n
  end
  for key,n in pairs(parsed) do F.db[key]=n end
  F.priceCache={}; return true
end
-- All calculations are in copper. Owned materials still carry replacement cost.
function F.Evaluate(recipe, settings, quote, deposit)
  local r = { estimated = false, materialsComplete = not recipe.problem, recipe = recipe, cost = 0, lines = {}, missing = {}, warnings = {} }
  local crafts = settings.crafts
  local quantities, order = {}, {}
  for _, reagent in ipairs(recipe.reagents or {}) do
    if not quantities[reagent.itemID] then order[#order+1] = reagent.itemID; quantities[reagent.itemID] = 0 end
    quantities[reagent.itemID] = quantities[reagent.itemID] + reagent.qty
  end
  for _, itemID in ipairs(order) do
    local reagent = { itemID = itemID, qty = quantities[itemID] }
    local quantity = reagent.qty * crafts
    local price, source, warning, evidence = quote(reagent.itemID, quantity, true)
    if evidence and evidence.kind == "estimate" then r.estimated = true end
    r.lines[#r.lines + 1] = { itemID = reagent.itemID, quantity = quantity, price = price, source = source, evidence = evidence }
    if price == nil then r.materialsComplete=false; r.missing[#r.missing + 1] = 'Reagent ' .. reagent.itemID
    else r.cost = r.cost + price end
    if warning then r.warnings[#r.warnings + 1] = warning end
  end
  r.quantity = recipe.made * crafts
  local value, source, warning
  if recipe.output then value, source, warning = quote(recipe.output, r.quantity, false) end
  r.source = source
  if warning then r.warnings[#r.warnings + 1] = warning end
  if value == nil then r.missing[#r.missing + 1] = 'Output price' end
  if recipe.problem then r.missing[#r.missing + 1] = recipe.problem end
  if recipe.output then r.deposit, r.depositSource = deposit(recipe.output, r.quantity, settings.duration) end
  if #r.missing == 0 then
    r.value = value
    r.fee = math.ceil(value * settings.cut / 100)
    r.profit = value - r.fee - r.cost
    if r.deposit ~= nil then
      r.adjusted = r.profit - r.deposit * settings.failures
      r.capital = r.cost + r.deposit * (settings.failures + 1)
      r.roi = r.cost > 0 and r.adjusted / r.cost * 100 or 0
    end
  end
  r.needsDeposit=r.deposit==nil
  return r
end
function F.CraftingRecipes()
  local recipes={}
  for id,recipe in pairs(F.db.recipes) do recipes[id]=recipe end
  for id,recipe in pairs(F.CatalogueRecipes and F.CatalogueRecipes() or {}) do
    -- Reference entries become craftable only with current character evidence.
    if recipe.knowledgeVerified and (recipe.learned==true or (recipe.learned==false and recipes[id])) then recipes[id]=recipe end
  end
  return recipes
end
function F.Results()
  local results = {}
  F.excluded = { above = 0, unknown = 0, stale = 0, unsupported = 0, unlearned = 0 }
  F.priceCache = {}
  for _, recipe in pairs(F.CraftingRecipes()) do
    local eligible, reason = F.Eligible(recipe)
    if eligible then
      results[#results + 1] = F.Evaluate(recipe, F.db, F.Quote, F.Deposit)
    elseif F.excluded[reason] then
      F.excluded[reason] = F.excluded[reason] + 1
    end
  end
  table.sort(results, function(a, b)
    -- Match the Sale profit column. Confidence and failed-listing losses are
    -- shown separately; neither should move a lower sale profit above a higher one.
    local ap, bp = a.profit or -math.huge, b.profit or -math.huge
    if ap == bp then
      if a.recipe.name == b.recipe.name then return a.recipe.id < b.recipe.id end
      return a.recipe.name < b.recipe.name
    end
    return ap > bp
  end)
  return results
end

-- Explicitly bounded planning: report the best total profit among 1..100 crafts.
function F.PlanBatch(recipe)
  F.priceCache={}
  local best, supported = nil, 0
  local previousWork=F.planningWork
  local work={remaining=500000}; F.planningWork=work
  local settings = {}; for key, value in pairs(F.db) do settings[key] = value end
  for crafts = 1, 100 do
    settings.crafts = crafts
    local ok,row = pcall(F.Evaluate,recipe,settings,F.Quote,F.Deposit)
    if not ok then F.planningWork=previousWork; F.Say('Batch calculation failed. Refresh the recipe and try again.'); return nil,0,true end
    if work.limited then break end
    if row.adjusted and not row.estimated then
      supported = supported+1
      if row.adjusted > 0 and (not best or row.adjusted > best.adjusted) then
        row.crafts = crafts; best = row
      end
    end
  end
  F.planningWork=previousWork
  return best, supported,work.limited or false
end
