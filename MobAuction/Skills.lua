local _, F = ...
function F.SkillLevel(profession)
  return F.db.skills[profession] or F.db.detectedSkills[profession]
end
function F.SetSkill(profession, value)
  if not F.professions[profession] then return false end
  if value == '' or value == 'auto' then F.db.skills[profession] = nil; return true end
  local n = tonumber(value)
  if not n or n < 0 or n > 1000 or n ~= math.floor(n) then return false end
  F.db.skills[profession] = n; return true
end
function F.UseDetectedLevels(selected)
  local found=F.DiscoverProfessions()
  local changed,available=0,0
  for id,enabled in pairs(selected or F.db.selectedProfessions) do
    if enabled and found[id] then
      available=available+1
      if F.db.skills[id]~=nil then changed=changed+1 end
      F.db.skills[id]=nil
    end
  end
  return changed,available,found
end
function F.SkillStatus(profession)
  local name=F.professions[profession] or 'Profession'
  local manual,detected=F.db.skills[profession],F.db.detectedSkills[profession]
  if manual~=nil then return name..': manual '..manual..' | detected '..(detected or 'unknown') end
  return name..': '..(detected and ('detected '..detected..' (automatic)') or 'skill not detected yet')
end
function F.SkillStatusSummary()
  if F.filter then return F.SkillStatus(F.filter) end
  local overrides={}
  for _,id in ipairs(F.ProfessionIDs()) do
    if F.db.selectedProfessions[id] and F.db.skills[id]~=nil then overrides[#overrides+1]=id end
  end
  if #overrides>0 then
    return F.SkillStatus(overrides[1])..(#overrides>1 and (' | '..(#overrides-1)..' more manual overrides in Character setup') or '')
  end
  return 'Skills follow detected levels. Character setup shows each profession\'s rank.'
end
function F.RequiredSkill(recipe)
  local manual = F.db.requirements[recipe.id]
  if type(manual) == 'table' and manual.build == F.Build() then return manual.rank, 'Manually confirmed for this build', 'manual' end
  local observed = F.db.verifiedRequirements[recipe.id]
  if observed and observed.build == F.Build() and observed.profession == recipe.profession and observed.output == recipe.output then
    return observed.rank, 'Trainer: ' .. observed.source, 'verified'
  end
  return nil, 'Minimum skill not verified', 'unknown'
end
function F.Eligible(recipe)
  if F.currentProfessionsComplete and F.currentProfessions and not F.currentProfessions[recipe.profession] then return false, 'profession' end
  if not F.db.selectedProfessions[recipe.profession] then return false, 'profession' end
  if F.filter and recipe.profession ~= F.filter then return false, 'profession' end
  if recipe.observedBuild ~= F.Build() then return false, 'stale' end
  if recipe.problem then return false, 'unsupported' end
  if recipe.learned == false and not F.db.includeUnlearned then return false, 'unlearned' end
  local level = F.SkillLevel(recipe.profession)
  if level == nil then return false, 'unknown' end
  local required = F.RequiredSkill(recipe)
  if required and required > level then return false, 'above' end
  if recipe.learned == false then
    if not required then return false, 'unknown' end
    if not recipe.trainerAvailable or not recipe.trainerSeen or time()-recipe.trainerSeen > 3600 then return false, 'unlearned' end
  elseif not required then
    -- Being learned at an observed skill proves eligibility there, not its minimum rank.
    if not recipe.observedSkill or level < recipe.observedSkill then return false, 'unknown' end
  end
  return true
end
-- Searching prices is also useful for unlearned recipes and unknown minimums.
-- It does not make those recipes eligible for crafting or Worth Learning.
function F.ScanEligible(recipe)
  if not F.db.selectedProfessions[recipe.profession] or (F.filter and recipe.profession~=F.filter)
      or (F.currentProfessionsComplete and F.currentProfessions and not F.currentProfessions[recipe.profession]) then return false,'profession' end
  if recipe.observedBuild~=F.Build() then return false,'stale' end
  if recipe.problem or not recipe.output or not recipe.reagents or #recipe.reagents==0 then return false,'unsupported' end
  local required,level=F.RequiredSkill(recipe),F.SkillLevel(recipe.profession)
  if level and ((required and required>level) or (recipe.learned and not required and recipe.observedSkill and level<recipe.observedSkill)) then return false,'above' end
  return true
end
function F.ScanStatus()
  local total,selected,eligible,older,counts=0,0,0,0,{}
  for _,recipe in pairs(F.db.recipes) do
    total=total+1
    if recipe.importNeedsRefresh then older=older+1 end
    if F.db.selectedProfessions[recipe.profession] and (not F.filter or recipe.profession==F.filter) then
      selected=selected+1
      local ok,reason=F.ScanEligible(recipe)
      if ok then eligible=eligible+1 else counts[reason]=(counts[reason] or 0)+1 end
    end
  end
  local profession=F.filter and F.professions[F.filter] or 'your crafting profession'
  local term=F.RecipeTerm(F.filter,true)
  local importHelp='Open '..profession..' in WoW to import its '..term..' automatically as they load; expand groups in older profession windows. Saved '..term..' remain available after you close the profession window.'
  local heading
  if F.filter then
    heading=profession..': '..selected..' '..F.RecipeTerm(F.filter,selected~=1)..' saved; '..eligible..' ready for price searches.'
  else
    heading=selected..' recipes saved for your selected professions; '..eligible..' ready for price searches.'
  end
  local lines={heading}
  local references=0
  for id,recipe in pairs(F.CraftingRecipes and F.CraftingRecipes() or {}) do
    if recipe~=F.db.recipes[id] and F.Eligible(recipe) then references=references+1 end
  end
  if references>0 then lines[#lines+1]=references..' additional learned reference entries are ready to compare from current character evidence.' end
  lines[#lines+1]='Full AH scan covers the entire market regardless of imported recipe counts.'
  if total==0 and not F.filter then lines[#lines+1]='No recipes imported yet.' end
  if F.recipeImportStatus then lines[#lines+1]=F.recipeImportStatus end
  if total>selected then lines[#lines+1]='Across all professions: '..total..' saved entries. This total includes other professions and older imports.' end
  if older>0 then lines[#lines+1]=older..' older entries need repair because their profession labels were not verified. They are excluded from crafting and price scans until refreshed.' end
  if total==0 or selected==0 or older>0 then lines[#lines+1]=importHelp end
  if counts.profession then lines[#lines+1]=counts.profession..' belong to professions no longer detected on this character. Check Character setup.' end
  if counts.stale then lines[#lines+1]=counts.stale..' need their recipe data refreshed. Reopen those professions to update them automatically; saved imports can then be used at the AH with the profession closed.' end
  if counts.above then lines[#lines+1]=counts.above..' above your selected skill. Use detected levels restores your current rank; Character setup shows manual overrides.' end
  if counts.unsupported then lines[#lines+1]=counts.unsupported..' have missing or unsupported recipe data. See Catalogue for each reason.' end
  if F.filter and F.db.skills[F.filter]~=nil then lines[#lines+1]=F.SkillStatus(F.filter)..'. Click Use detected levels to follow skill gains.' end
  return table.concat(lines,'\n')
end
function F.DetectSkill(profession, info)
  F.DiscoverProfessions()
  local rank = info and info.skillLevel
  if type(rank) == 'number' and rank > 0 then
    F.db.detectedSkills[profession] = rank
    F.currentProfessions=F.currentProfessions or {}; F.currentProfessions[profession]=rank
  end
end
