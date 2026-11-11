# Dashboard Surface

This package provides the shared infrastructure for dashboard surface pages (cross-repo and repo-scoped list views with sidebar navigation, search, and saved views).

## Architecture

Each dashboard surface implements the same pipeline:

```
SearchConfig → ResultsLoader → Payloads → Controller → React app
```

| Layer | Responsibility |
|-------|---------------|
| **SearchConfig** | Translates request params + path into an Elasticsearch query string |
| **ResultsLoader** | Loads models from search results, prefills associations, builds deferred data |
| **Payloads** | Serializes models into React-consumable JSON (route payloads) |
| **Controller** | Orchestrates the pipeline, handles layout/content/deferred actions |

## Shared infrastructure (future `dashboard_surface_core`)

These files are consumed by multiple surfaces and will eventually be extracted into a dedicated core package:

| File | What it provides |
|------|-----------------|
| `payloads/layout.rb` | Shared layout serializer (sidebar, filters, saved views, repos) |
| `payloads/current_user.rb` | Current user payload for app-level hydration |
| `payloads/saved_view.rb` | Saved view (SearchShortcut) serialization |
| `payloads/sidebar_links.rb` | `SidebarLink` struct + serializer (each surface provides its own links) |
| `payloads/label.rb` | Label struct shared across issue and PR result payloads |
| `pagination.rb` | Pagination struct (current_page, total_pages, total_count) |
| `loaders/saved_view_loader.rb` | Loads saved views by search type (issues, pull_requests, repositories) |
| `loaders/selected_repos_loader.rb` | Resolves `repo:owner/name` filter terms to Repository objects |

## Surfaces

| Surface | Package | Owner |
|---------|---------|-------|
| Pulls | `packages/dashboard_surface/` | `:pull_requests.signup_flow` |
| Issues | `packages/issues_dashboard_surface/` | `:signup_flow.issues` |

## Adding a new surface

Use `packages/issues_dashboard_surface/` as the reference implementation:

1. **Create a package** with `package.yml` (no enforced dependencies needed initially)
2. **Implement Queries** — constants for your named ES query strings
3. **Implement SearchConfig** — translates params/path to `es_query`, `page`, `maximum_result_limit`
4. **Implement ResultsLoader** — `main_content_from` (immediate content) + `deferred_content_from` (lazy-loaded data)
5. **Implement Payloads** — result serializer, search results wrapper, deferred content, sidebar links
6. **Implement Controller** — `layout`, `index`, `content`, `deferred` actions using `respond_with_react`
7. **Add routes** in `config/routes/`
8. **Add SERVICEOWNERS** entry and run `bin/generate-service-files.rb`

### Naming conventions

| Layer | Pattern |
|-------|---------|
| Module | `YourSurfaceDashboardSurface::*` (e.g., `IssuesDashboardSurface::SearchConfig`) |
| Controller | `YourSurfaceDashboardSurfaceController` |
| Route IDs | `camelCase` (e.g., `issuesDashboardSurfaceContentRoute`) |
| React bundle | `"dashboard-surface"` (shared) or own app for web vitals isolation |
| Metrics prefix | `your_surface_dashboard_surface.*` |
| Feature flag | `your_surface_dashboard_surface` |
