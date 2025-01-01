# Migration Step: Refactor Entrypoints

- **You must always read in and follow the referenced diff file (`refactor_entrypoints_for_query_routes.diff`) as your primary source of truth for code structure, naming, and placement.**
- For every migration, before making any changes:
  - **Read the entire referenced diff file.**
  - Use the diff as your step-by-step guide. **Do not deviate from the structure, naming, or placement shown in the diff.**
  - All code changes, including component signatures, exports, imports, and usage in tests/stories, must match the diff as closely as possible.
  - **IMPORTANT: If there are payload types used in both routes and components, ensure they are imported from a shared types file (e.g., `../types/payloads.ts`) to prevent circular dependencies.**
  - For each route/component, update the original component to accept a `payload` prop and remove its export, matching the diff.
  - If the application has more than 4 routes, only attempt to perform the needed steps for up to 4 routes. Repeat the process in batches until all routes have been migrated.
  - In the same file containing the existing `Entrypoint` component, define and export two entrypoint components:
    - `<ComponentName>EntrypointFuture` uses `useRouteQuery` with the correct route and `mainQuery` name, destructures the `data` property from the return value and renames it to `payload` (e.g. `const {data: payload} = useRouteQuery(...)`), and passes the payload to the original component, as in the diff.
    - These components should always be created in an existing file—never create any new files for the entrypoints.
    - For **Data Router routes**, you must create a **unique `EntrypointFuture` component for each route**, but place it in the same file as the existing `Entrypoint` component (not in a new file). **Do not share entrypoint components between Data Router routes, even if they render the same page component.**
             > **Example:**
      > ```tsx
      > // For /foo and /bar, both rendering <MyPage />
      > export function FooEntrypointFuture() {
      >   const {data: payload} = useRouteQuery(fooRoute, 'mainQuery')
      >   return <MyPage payload={payload} />
      > }
      > export function BarEntrypointFuture() {
      >   const {data: payload} = useRouteQuery(barRoute, 'mainQuery')
      >   return <MyPage payload={payload} />
      > }
      > ```
      > **Common mistake:** ❌ Do NOT share a single entrypoint between multiple Data Router routes.
  - Update route registration to use the new entrypoint components in the DataRouter app. In the `Component` field of each route, always use `<ComponentName>EntrypointFuture` for data router app registration, as in the diff. Do not use the original component in these registrations.
  - Ensure `<ComponentName>EntrypointFuture` methods are imported.
  - **Verify** the changes made are using the `<ComponentName>EntrypointFuture` for data router app registration.
  - Ensure all code compiles and imports are placed as in the diff.
  - Update all tests and stories to use the entrypoint component instead of the original, as shown in the diff. All references to the old component must be replaced with the entrypoint. Tests are often found in the `__tests__` directory of the package, so search there for references to the components that are now no longer updated and replace them with references to the appropriate entrypoint component.
  - **Do not add extra code, comments, or examples.**
  - Before making any changes, summarize what changes you will make, referencing the diff. If your summary includes any new files not shown in the diff, it is incorrect—try again.
- **Every time you perform this migration step, the referenced diff must be read and used as the main driver for your changes.**
- **After refactoring the entrypoints, run the appropriate lint and type-checking commands (see starting instructions) to identify any circular dependencies or other issues:**
  - If any issues arise, especially circular dependencies, extract shared types to a separate file immediately
