# DataRouter Migration: Application Migration Prompt

## Objective

Guide the Copilot agent to collect required migration context and execute subsequent migration steps for transitioning an application to use DataRouter.

## Instructions

### Step 1: Gather Required Information

- Derive or request the following from context if cannot be derived:
  - `package-name`: Package name
  - `path-to-package` Package directory (e.g., usually `ui/packages/<package-name>` or `app/assets/modules/<package-name>`)
  - `path-to-app`: Find the path to the client app entry point that calls `registerNavigatorApp` with the param set to `package-name`
  - `path-to-controller`: Find the path to the server controller that has the `react_bundle_name` set to `package-name`, or searching for the filename using the format `snake_case(<package-name>)_controller.rb`
  - `controller-actions`: Find the controller actions to update based on the routes defined in `path-to-app` and methods `path-to-controller` with the aid of the routes file `config/routes.rb`
  - `routes-list`: Find and identify all the routes that need to be migrated for tracking purposes

If these values are not provided, ask for each value individually.

### Step 2: Confirm Information

- Confirm with the user that the above values are correct before proceeding.

### Step 3: Setup ESLint Environment

- **Detect environment and setup ESLint:**
  - Check if running in GitHub Actions: `echo $GITHUB_ACTIONS`
  - If in GitHub Actions (value is "true"), install ESLint globally: `npm install -g eslint`
  - Test ESLint installation by running: `eslint --version`
  - If ESLint is not available globally or npm workspace commands fail, install it globally as fallback

### Step 4: Use as Context

- Use these values as context for all subsequent migration prompts and actions.

### Step 5: Execute Migration Prompts

- **Ask if you want to commit changes individually.** If so, stop after each step and ask if the user would like to create a commit for the changes. Otherwise, proceed through all steps and prompt with minimal interruption.
- **For each migration step, follow this process:**
  1. Announce the step with its title.
  2. Plan your actions and gather all necessary context before making changes. If you are missing information, ask the user for it.
  3. Use tools to read files and gather information—never guess or make up answers.
  4. Make small, testable, incremental changes.
  5. Run and validate after EACH migration step (not just at the end):
      - **Run the appropriate eslint command** (set up in Step 3):
        - If the package exists in `ui/packages`, run: `npm run lint -w @github-ui/<package-name> -- --fix`, `npm run tsc -w @github-ui/<package-name>` and `npm run test -w @github-ui/<package-name>`
        - If the package exists in `app/assets/modules`, run: `npm run lint -w @github-ui/app-assets-modules -- --fix` and `npm run tsc -w @github-ui/app-assets-modules`
        - As a fallback, if npm workspace commands fail, use: `eslint . --fix` (from the package directory)
      - Attempt to fix any remaining errors after each validation step.
  6. **Watch for circular dependencies:** If you encounter circular dependency errors, extract shared types (especially payload types) to a separate file (e.g., `types/payloads.ts`).
  7. **Always check git status:** Before committing, run `git status --porcelain` and ensure no files in `node_modules` are being modified or added. Never commit changes to `node_modules` folders.
  8. Reflect on the outcome and adjust if needed.
  9. Compare the diff that this step generated to the diff that is referenced in the prompt. If extra files are added or the changes differ significantly, try again, with a goal to match the diff as closely as possible.
  10. Once you have a plan, do not stray from it. Remember the original prompt that you read in from the markdown file in the step and do not try to alter the prompt to fill in any gaps or make any assumptions. If the prompt that you read in from the markdown file is unclear, ask for help instead of trying to guess. The .diff file that is referenced by the prompt in the markdown file is the source of truth.
  11. If you ever get stuck, or aren't sure what to do: Stop, re-read the referenced diff and make a plan to follow those changes exactly.
- **Migration steps (in order) - all of these files are found in ui/packages/react-core/future/docs/data-router/migration/:**
  - 1_refactor_entrypoints_for_json_routes_prompt.md
  - 2_refactor_components_with_use_route_payload_prompt.md
  - 3_create_app_builder_prompt.md
  - 4_create_and_register_app_prompt.md
  - 5_create_routes_prompt.md
  - 6_add_routes_to_app_prompt.md
  - 7_refactor_entrypoints_for_query_routes_prompt.md
  - 8_migrate_or_remove_app_component_prompt.md
  - 9_update_controllers_prompt.md
  - 10_add_tests_prompt.md
  - 11_validation_step_prompt.md
- **Important pre-commit checks:**
  - **Always run lint and fix errors:** After each step, run the appropriate eslint command (see Step 3)
  - **Ensure proper newlines:** Every file must end with exactly one newline character. Use the appropriate eslint command to automatically fix these issues.
  - **Look for circular dependencies:** If found, extract shared types to a separate module (e.g., `types/payloads.ts`)
  - **Check for node_modules changes:** Run `git status --porcelain | grep node_modules` to ensure you're not committing any files in node_modules

### Step 6: Important Safety Rules

- **Never modify files outside the target package**
  - Focus only on the specific package being migrated
  - Do not make changes to shared libraries or dependencies

- **Never commit node_modules files**
  - Before any commit, run: `git status --porcelain | grep node_modules`
  - If any node_modules files appear in the status, do not commit them
  - Use `git restore <path>` to revert any changes to node_modules files
  - If node_modules files are not cleaned up when running with --fix, manually discard those changes

- **Prevent circular dependencies**
  - Extract shared types and interfaces to dedicated type files
  - Place payload types used by both components and routes in a separate module
  - Watch for TypeScript errors about circular dependencies and fix immediately

- **Run validation frequently**
  - Run lint, type checking, and tests after each step
  - Fix errors as they appear rather than letting them accumulate
  - Use the appropriate eslint command (see Step 3 setup): `npm run lint -w @github-ui/<package-name> -- --fix` or `eslint . --fix` as fallback
