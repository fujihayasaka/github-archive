# Migration Step: Create and Register Data Router App

- **You must always read in and follow the referenced diff file (`create_and_register_app.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including imports, registration, and placement, must match the diff as closely as possible.
  - In the file with `registerNavigatorApp`, import the app builder using a relative path, as in the diff.
  - After the navigator app registration, create and register the data router app using the pattern in the diff.
  - Do NOT remove or modify any existing `registerNavigatorApp` or related legacy app registration code unless shown in the diff.
  - Only add the new Data Router app registration (using `registerDataRouterApp` and the `DataRouterApplicationBuilder`) alongside the existing code, as in the diff.
  - Do not comment out, omit, or add extra comments or TODOs to the data router registration. The new registration must be active and present in the file, not commented out or left as a placeholder.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
