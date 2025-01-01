# Migration Step: Create App Builder

- **You must always read in and follow the referenced diff file (`create_app_builder.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including file placement, exports, imports, and naming, must match the diff as closely as possible.
  - Place the app builder in a `/config/app-builder.ts` file in the package directory, as shown in the diff.
  - Import `DataRouterApplicationBuilder` from `@github-ui/react-core/future/data-router-application` as in the diff.
  - Export a constant named `<packageNameCamelCase>AppBuilder` using `DataRouterApplicationBuilder.create('<package-name>')`, matching the diff.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
