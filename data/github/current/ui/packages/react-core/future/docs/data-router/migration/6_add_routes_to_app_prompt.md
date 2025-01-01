# Migration Step: Add Routes to App

- **You must always read in and follow the referenced diff file (`add_routes_to_app.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including imports, array structure, and registration, must match the diff as closely as possible.
  - Import all new routes in the main file for the package, as in the diff.
  - If the application has more than 4 routes, only attempt to perform the needed steps for up to 4 routes. Repeat the process in batches until all routes have been migrated.
  - Add each route to the `createDataRouterAppFromRoutes` array, using the `.toRoute({Component})` pattern, matching the diff.
  - Register the data router app with `registerDataRouterApp`, as in the diff.
  - **After adding routes, check for circular dependencies between route files and component files, especially via payload types.**
  - **If a circular dependency is found, extract the shared types (such as payload types) into a new module (e.g., `routes/payload-types.ts`), and update all imports to use this new module, as in the diff.**
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
