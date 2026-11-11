# Runtime Engineering Guidelines

These guidelines apply to all changes made under the `runtime` folder.

- We lint our code with `eslint` to find problematic coding patterns.
   - Running `npm run lint` from within the `runtime` folder will check the code for `eslint` errors.
   - You **MUST** run `npm run lint` before finishing your work or using tools which commit changes/report progress (e.g. **report_progress**). 
   - Changes that have lint errors will fail in CI.
- We enforce style guidelines with `prettier`.
   - Running `npm run format` from within the `runtime` folder will automatically format the code according to our style guidelines.
   - You **MUST** run `npm run format` before finishing your work or using tools which commit changes/report progress (e.g. **report_progress**).
   - Changes that have style errors will fail in CI.
- If being asked to make changes to a specific test, test file, or set of test files, **do not** run the full test suite unless you are specifically asked to do so. Instead only run the tests you are modifying.
