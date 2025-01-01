# Migration Step: Migrate or Remove App Component

- **You must always read in and follow the referenced diff file (`remove_app_component.diff` or `migrate_app_component.diff`, depending on the evaluation from this step) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including file deletion, exports, imports, and registration, must match the diff as closely as possible.
  - If the `App` component is completely empty (renders only `props.children` and nothing else), delete the file and remove all references, including from tests, stories, and registration, as in the diff. Ensure all references to the old App component are removed or replaced as required by the migration.
    - Follow the pattern in `remove_app_component.diff` if this is the case.
    - If the App.tsx file is now empty, either try to delete it or give the user instructions on how to delete it, as in the diff.
  - If the `App` component renders any additional elements, providers, or logic (such as a layout wrapper, context providers, or other UI like `PreviewCardOutlet`), you must migrate it to a parent route in the data router application, as in the diff. This means:
    - Following the pattern in `migrate_app_component.diff`, add an object with `Component: App` and a `children` array containing your existing routes to the array passed to `createDataRouterAppFromRoutes`, as in the diff.
    - Do not use or invent any API like `createLayoutRouteConfig` unless it is shown in the diff. Only use the object/children structure as in the diff.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
