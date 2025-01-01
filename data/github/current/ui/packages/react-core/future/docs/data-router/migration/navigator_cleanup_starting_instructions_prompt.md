# DataRouter Migration: Navigator App Cleanup Prompt

## Objective

Guide the Copilot agent to clean up the navigator app and related code after successfully migrating to Data Router. This prompt is designed to be used after a module has been fully migrated to use Data Router and the team is ready to remove the old navigator app implementation.

## Instructions

### Step 1: Gather Required Information

- Derive or request the following from context:
  - `module`: Module name that has been migrated to Data Router (e.g., 'activity', 'secret-scanning', 'github-models')
  - `package-path`: Path to the package (e.g., `ui/packages/<package-name>` or `app/assets/modules/<package-name>`)
  - `path-to-app`: Path to navigator app entry point (typically an index.ts file that contains registerNavigatorApp call)
  - `path-to-controller`: Path to server controller(s) that may reference the navigator app

If these values are not provided, ask for each value individually.

### Step 2: Confirm Information

- Confirm with the user that the above values are correct before proceeding.

### Step 3: Execute Cleanup

Follow these steps carefully, one at a time:

1. **Remove navigator app registration**
   - Find and remove the call to `registerNavigatorApp` for the specified module
   - Look for code like: `registerNavigatorApp('<module-name>', () => ({ ... }))`
   - Leave the registration of the data router application in place (calls to `createDataRouterAppFromRoutes` or `registerDataRouterApp`)
   - If the file is now empty or only contains imports, consider removing it entirely

2. **Remove entrypoint components**
   - Remove any entrypoint components referenced in the deleted jsonRoutes
   - These are typically components named `<Module>Entrypoint` or similar
   - Look for: `jsonRoute({path: '...', Component: <Module>Entrypoint})`
   - Only remove components that were exclusively used by the navigator app
   - Make sure these components are not used by the Data Router app

3. **Update controller actions**
   - Find controller actions that call `render_react_app` for the navigator app
   - Look for Rails code like: `render_react_app("navigator.<module-name>")`
   - Remove these calls, leaving only the data router app logic (e.g., `respond_with_react`)
   - **IMPORTANT**: Remove ALL feature flag conditionals related to the Data Router migration:
     - Remove the complete conditional structure (if/else/end blocks), not just parts of it
     - Remove any helper methods related to feature flags (e.g., `data_router_feature_flag_enabled?`)
     - Don't leave any `end` statements or partial conditional code behind
   - Ensure all controller actions still function properly after removal
   
   Example of complete removal:
   ```ruby
   # Before:
   def show
     if data_router_feature_flag_enabled?
       respond_with_react
     else
       render_react_app("navigator.my-module")
     end
   end
   
   private
   
   def data_router_feature_flag_enabled?
     # Feature flag check logic
   end
   
   # After:
   def show
     respond_with_react
   end
   ```

4. **Remove navigator-specific tests**
   - Delete all test files that specifically test navigator app components
   - Look for test files with patterns like `*_spec.rb`, `*.test.ts`, or `*.test.tsx` that test navigator app components
   - Do NOT attempt to update these tests to use the Future entrypoint components
   - Data router functionality should have separate test files that already exist
   - When in doubt, delete the test file rather than trying to modify it

### Step 4: Validation

- **For each cleanup step, validate your changes:**
  - If the package exists in `ui/packages`, run: 
    ```
    npm run lint -w @github-ui/<package-name> -- --fix
    npm run tsc -w @github-ui/<package-name>
    ```
  - If the package exists in `app/assets/modules`, run: 
    ```
    npm run lint -w @github-ui/app-assets-modules -- --fix
    npm run tsc -w @github-ui/app-assets-modules
    ```
  - Run relevant tests to ensure the application still works:
    ```
    npm run test -w @github-ui/<package-name>
    ```
  - **Pay careful attention to syntax errors** and ensure that:
    - No conditional logic remains partially removed (e.g., missing `end` statements)
    - No unused helper methods remain that were related to feature flags
    - Code is syntactically correct and properly indented
- **Enhanced safety checks:**
    - Run `git status --porcelain | grep node_modules` to ensure you're not committing any files in node_modules
    - Run `git diff --numstat` to verify the scope of changes and ensure only intended files are modified
    - Check that deleted lines are not more than twice the number of inserted lines per file (indicates potential over-deletion)
    - Use `git restore <file>` if too much deletion is detected in any file
  - Verify the app still loads correctly in the browser
  - Verify all routes still work that used to be handled by the navigator app

### Step 5: Important Safety Rules
- **Never modify files outside the target package**
  - Focus only on the specific package being cleaned up
  - Do not make changes to shared libraries or dependencies
  - **NEVER modify files in node_modules/ directories unless absolutely necessary for the specific task**
- **Never commit node_modules files**
  - Before any commit, run: `git status --porcelain | grep node_modules`
  - If any node_modules files appear in the status, do not commit them
  - Use `git restore <path>` to revert any changes to node_modules files
  - **Enhanced node_modules protection**: Run `git diff --numstat` before committing to verify only intended files are changed
  - **Check .gitignore patterns**: Ensure node_modules are properly excluded and review changes with `git diff` before committing
  - **Avoid broad file operations**: Be extra careful with file operations that might affect symlinks or dependencies
- **Scope limitations and file operation safeguards**
  - When making changes, focus only on the specific files mentioned in the cleanup task
  - Avoid touching package management files, dependencies, or build artifacts unless required
  - Always use `git diff` to review changes before committing
  - Use targeted file editing instead of broad file operations

## Cleanup Prompt

Remove the navigator app version of the `<MODULE>` module:

**IMPORTANT: Before making any changes, ensure you will not modify files in node_modules/ directories. Use targeted file operations and run `git status --porcelain | grep node_modules` and `git diff --numstat` to verify changes before committing.**

1. Remove the app registration for the call to registerNavigatorApp for `<MODULE>`. 
   - Look for: `registerNavigatorApp('<MODULE>', () => ({ ... }))`
   - Leave the registration of the data router application in place 
   - Continue to use the appbuilder to call createDataRouterAppFromRoutes

2. Remove related entrypoint components from the json routes that were deleted (typically the `<MODULE>Entrypoint` component).
   - Only remove components that were exclusively used by the navigator app

3. Update controller actions to remove any calls to render_react_app for the navigator app, leaving only the data router app logic.
   - Look for: `render_react_app("<MODULE>")`
   - Remove ALL feature flag conditionals and helper methods (if/else/end blocks) related to the Data Router migration
   - Ensure no partial conditional code or unused `end` statements remain

4. Remove tests that only applied to the old navigator app version.
   - Delete all test files that tested navigator app components assuming they don't render any data router routes
   - Do NOT update tests to use the Future entrypoint components
   - Data router functionality should have separate test files

Do these steps one at a time, pausing after each step for validation.
