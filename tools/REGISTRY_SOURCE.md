# Recipe Registry Forever source research

Inspected 2026-11-12 using the primary public repository and raw source.

- Repository: https://github.com/colettamattia91-cloud/Recipe-Registry
- Data: https://raw.githubusercontent.com/colettamattia91-cloud/Recipe-Registry/main/RecipeRegistry_Forever/Data/Metadata/RecipeMetadata_Generated.lua
- License: https://raw.githubusercontent.com/colettamattia91-cloud/Recipe-Registry/main/LICENSE
- MIT, Copyright (c) 2026 colettamattia91-cloud.
- Optional addon folder: RecipeRegistry_Forever (distinct from the TBC RecipeRegistry folder).
- Global: RecipeRegistryRecipeMetadata. schemaVersion=1; flavor='forever'; metadataVersion='forever-1.60.1.70790' on the freshest fetched page.
- recipesBySpellId[craftSpellID] contains profession, createdItemId, optional createdCount/createdCountMax, recipeItemId, requiredSkill, reagents={{itemId,count}}, bopOutput, removed, sourceKind, sourcePlaces, plus navigation fields.
- Generated header reports 2,520 records across 12 professions, 2,337 output IDs, 2,001 recipe-item mappings, 2,344 minimum-skill fields, 284 removed entries. These are the maintainer's reported counts, not a local full-file count. README and an older cached raw response still report 2,519.
- Latest header says structure/reagents prefer game-file mining build70790 over the older live API dump69913. Neither historical source proves current character knowledge or current live learnability.
- Professions: alchemy, blacksmithing, cooking, enchanting, engineering, first_aid, fishing, herbalism, leatherworking, mining, skinning, tailoring.
- Savory Stag Sliders: [1250142], profession='cooking', createdItemId=250065, recipeItemId=250173, requiredSkill=225, reagents5471x2 and2692x3, bopOutput=false. createdCount absent (schema default one). No sourceKind/sourcePlaces in this record.
- Overrides global: RecipeRegistryRecipeMetadataOverrides. Currently empty createdItemBySpellId, recipeItemBySpellId, categoryBySpellId, selfOnlyOutputlessBySpellId, bopOutputBySpellId, bindTypeByCreatedItemId tables.

Shell urllib access failed with DNS resolution unavailable. No permission escalation was attempted. Web raw files were readable but only excerpted; no complete database or commit pin was downloaded. Optional tools/fetch_registry_reference.py archives a commit-pinned database plus MIT license and provenance when ordinary network access is available. It does not execute Lua, install an addon, or generate files loaded by MobAuction. Runtime adapter is the user-facing route.
