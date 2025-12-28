# Code Optimization Prompt for Palworld-Bridge v1.4.0

**Task**: Review and optimize all code files in the Palworld-Bridge project while maintaining current functionality.

---

## Instructions

Perform a comprehensive code review and optimization of the entire Palworld-Bridge project located at:
```
/home/zmedh/Takaro-Projects/Palworld-Bridge
```

### What to Optimize

1. **TypeScript/JavaScript Files** (`src/*.ts`, `TakaroChat/Scripts/*.lua`)
   - Remove unused imports, variables, and functions
   - Simplify complex logic without changing behavior
   - Optimize loops and conditionals
   - Remove commented-out code
   - Fix inconsistent formatting
   - Consolidate duplicate code

2. **Code Quality**
   - Remove redundant error handling
   - Simplify nested conditionals
   - Remove dead code paths
   - Optimize data structures (Maps, Sets, Arrays)
   - Remove console.log/debug statements that aren't needed

3. **Performance**
   - Optimize async/await patterns
   - Remove unnecessary awaits
   - Optimize polling intervals if excessive
   - Cache frequently accessed values
   - Remove redundant API calls

4. **Lua Scripts** (`TakaroChat/Scripts/*.lua`)
   - Remove unused functions
   - Optimize loops and pcall usage
   - Remove excessive logging
   - Consolidate duplicate code

### Critical Rules - DO NOT:

❌ **DO NOT change functionality** - Code must work exactly the same after optimization
❌ **DO NOT fix errors** - Only document them in FoundErrors.md
❌ **DO NOT modify configuration files** - Leave TakaroConfig.txt, package.json dependencies unchanged
❌ **DO NOT remove features** - All working features must remain functional
❌ **DO NOT change API contracts** - Maintain all endpoints, actions, and response formats
❌ **DO NOT alter the build process** - Keep tsconfig.json and build scripts as-is

### What TO DO:

✅ **Remove unused code** - Functions, variables, imports that are never called
✅ **Simplify logic** - Reduce nesting, use early returns, simplify conditions
✅ **Consolidate duplicates** - Merge identical code blocks into reusable functions
✅ **Optimize patterns** - Better async/await usage, efficient loops
✅ **Document errors** - Create FoundErrors.md for any bugs/issues found
✅ **Clean formatting** - Consistent indentation, remove trailing whitespace

---

## Files to Review

### TypeScript (Bridge)
- `src/index.ts` - Main bridge application
- `dist/*` - Skip (compiled output)

### Lua (TakaroChat Mod)
- `TakaroChat/Scripts/main.lua`
- `TakaroChat/Scripts/chat.lua`
- `TakaroChat/Scripts/events.lua`
- `TakaroChat/Scripts/discord.lua`
- `TakaroChat/Scripts/teleport.lua`
- `TakaroChat/Scripts/location.lua`
- `TakaroChat/Scripts/deep_discovery.lua`
- `TakaroChat/Scripts/inventory.lua` (if exists)
- `TakaroChat/Scripts/config.lua`
- `TakaroChat/Scripts/utils.lua`

### Configuration
- Review but DO NOT modify:
  - `package.json`
  - `tsconfig.json`
  - `TakaroChat/Scripts/config.lua`

---

## Error Documentation Format

If errors/bugs/issues are found, create `FoundErrors.md`:

```markdown
# Found Errors - Palworld-Bridge v1.4.0

## Critical Issues
List any critical bugs that could cause crashes or data loss

### [File]: [Function/Line]
- **Issue**: Description
- **Location**: file.ts:123
- **Impact**: How it affects functionality
- **Suggested Fix**: What should be done (DO NOT implement)

## Performance Issues
List performance problems

## Code Smells
List code quality issues that aren't bugs but should be improved

## Warnings
List potential issues that may cause problems in certain scenarios
```

---

## Optimization Checklist

Go through each file and check:

### TypeScript (`src/index.ts`)
- [ ] Remove unused imports
- [ ] Remove unused variables
- [ ] Remove unused functions
- [ ] Simplify complex conditionals
- [ ] Optimize async/await patterns
- [ ] Remove commented code
- [ ] Consolidate duplicate logic
- [ ] Remove debug logging
- [ ] Check for memory leaks (listeners, intervals)
- [ ] Optimize polling loops

### Lua Scripts
- [ ] Remove unused local variables
- [ ] Remove unused functions
- [ ] Optimize pcall usage
- [ ] Reduce excessive logging
- [ ] Simplify nested conditions
- [ ] Remove commented code
- [ ] Consolidate duplicate patterns
- [ ] Check for infinite loops
- [ ] Optimize string concatenation
- [ ] Check for memory leaks (LoopAsync cleanup)

---

## Output Format

For each file optimized, provide:

```
File: [filename]
Changes Made:
  - Removed unused function: functionName()
  - Simplified conditional in line 123
  - Consolidated duplicate code at lines 45-50 and 78-83
  - Removed 3 unused imports

Lines Saved: X
Estimated Performance Improvement: [None/Minor/Moderate/Significant]
```

---

## Testing Requirements

After optimization:
- Code must compile without errors (`npm run build`)
- All existing functionality must work identically
- No new TypeScript errors
- No new runtime errors

---

## Start Command

```
Review all files in /home/zmedh/Takaro-Projects/Palworld-Bridge following the optimization guidelines above.
Start with src/index.ts, then process all Lua files in TakaroChat/Scripts/.
Document any errors found in FoundErrors.md but DO NOT fix them.
Provide a summary of optimizations made for each file.
```

---

## Example Optimizations

### Before:
```typescript
if (condition) {
    if (anotherCondition) {
        if (thirdCondition) {
            doSomething();
        }
    }
}
```

### After:
```typescript
if (!condition || !anotherCondition || !thirdCondition) return;
doSomething();
```

### Before:
```typescript
const result = await someFunction();
const data = await anotherFunction();
// Both could run in parallel
```

### After:
```typescript
const [result, data] = await Promise.all([someFunction(), anotherFunction()]);
```

### Before (Lua):
```lua
local success, err = pcall(function()
    local success2, err2 = pcall(function()
        -- nested pcalls
    end)
end)
```

### After (Lua):
```lua
local success, err = pcall(function()
    -- consolidated error handling
end)
```

---

**Ready to optimize? Start the review now!**
