# Migration Step: Refactor useRoutePayload

- Refactor all usages of the `useRoutePayload` hook in the `<package-name>` package so that the payload is passed in as a prop (or argument) instead of being retrieved via the hook inside the component or hook.
- Update all components, providers, and hooks to accept the payload as a prop/argument, and ensure the payload is passed down from the top-level entrypoint.
- Update all usages and parents as needed until the package compiles.

- Please make the changes step by step, updating all affected files and their consumers, and let me know if any manual intervention is required.
- **Do not add extra code, comments, or examples.**