# Migration Step: Refactor Entrypoints


- **You must always read in and follow the referenced diff file (`refactor_entrypoints_for_json_routes.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including component signatures, exports, and usage in tests/stories, must match the diff as closely as possible.
  - Leave imports as is for now.
- Update the original component to accept a `payload` prop and remove its export, matching the diff.
  - If the application has more than 4 routes, only attempt to perform the needed steps for up to 4 routes. Repeat the process in batches until all routes have been migrated.
  - In the same file, define and export an entrypoint component named `<ComponentName>Entrypoint` that uses `useRoutePayload` and passes the payload to the original component, as shown in the diff.
  - Always create entrypoints in existing files—never create new files for entrypoints.
  - If multiple JSON route definitions reference the same component, re-use the same entrypoint for each case.
  - Update route registration to use the new entrypoint components for the Navigator app. In the `Component` field of each route, always use `<ComponentName>Entrypoint` for navigator app, as in the diff.
  - Ensure all code compiles and imports are placed as in the diff.
  - Remove any unnecessary imports from the file.
  - Update all tests and stories to use the entrypoint component instead of the original, as shown in the diff. All references to the old component must be replaced with the entrypoint. Tests are often found in the `__tests__` directory of the package, or end in `.test.tsx`, so search the app directory for these test files, and within all the test files you found, references to the components that are now no longer updated and replace them with references to the appropriate entrypoint component.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
