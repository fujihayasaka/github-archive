# DataRouter Migration: Final Validation Step

## Objective

Guide validation of completed DataRouter migration to ensure all code quality and functionality checks pass.

## Instructions

This is the final validation step after completing all previous DataRouter migration steps. Follow these instructions to ensure your code is ready for review.

## Final Validation Checklist

Follow these steps to validate that your DataRouter migration is complete and free of errors:

### Step 1: TypeScript Validation

Run the appropriate TypeScript command (see starting instructions) to check for type errors.

Fix any TypeScript errors that are reported. Pay special attention to:

- Type compatibility in route definitions and payloads
- Missing type declarations or imports
- Circular dependencies between modules

### Step 2: Linting Validation

Run the appropriate eslint command (see starting instructions) to address code style and quality issues.

Review any remaining lint errors that couldn't be automatically fixed and address them manually.

### Step 3: Test Validation

Run the appropriate test command (see starting instructions) to ensure all tests are passing.

If any tests are failing, review the test failures and fix your implementation to match expected behavior.

### Step 4: Node Modules Check

Ensure no files in `node_modules` are being tracked by Git:

```bash
git status --porcelain | grep node_modules
```

If any files in `node_modules` appear:

1. Remove them from staging:
   ```bash
   git restore --staged "**/node_modules/**"
   ```

2. Discard changes to them:
   ```bash
   git restore "**/node_modules/**"
   ```

### Step 5: Newline Verification

Ensure all files end with exactly one newline character using the appropriate eslint command (see starting instructions).

### Step 6: Circular Dependency Check

Check for circular dependencies in your code using the dependency cruiser:

```bash
npm run lint:dependencies
```

If circular dependencies are detected in your package, fix them by:

1. Extracting shared types to a dedicated type file (e.g., `types/payloads.ts`)
2. Reorganizing your module structure to avoid circular imports
3. Using interface merging or type augmentation when appropriate

## Final Pre-Commit Verification

Run a final validation to ensure everything is ready for commit:

1. Verify all TypeScript errors are fixed using the appropriate TypeScript command (see starting instructions)

2. Verify all linting errors are fixed using the appropriate eslint command (see starting instructions)

3. Verify all tests are passing using the appropriate test command (see starting instructions)

4. Verify no node_modules files are being tracked:
   ```bash
   git status --porcelain | grep node_modules
   ```

5. Verify all files have correct line endings.

Congratulations! Your DataRouter migration is now complete and validated. You may now commit your changes.