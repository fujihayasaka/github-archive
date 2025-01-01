import {getCSSEntryPoints, getJSEntryPoints, getSSREntryPoints, getStandaloneEntryNames} from '../entry-points'

describe('entry-points', () => {
  test('getJSEntryPoints', () => {
    const entries = getJSEntryPoints()

    // app/assets/modules/*.ts
    expect(entries['environment']).toBe('./app/assets/modules/environment.ts')

    // app/assets/workers/*.ts
    expect(entries['find-file-worker']).toBe('./app/assets/workers/find-file-worker.ts')

    // app/assets/preview_modules/*.ts
    expect(entries['query-builder-preview-mocks']).toBe('./app/assets/preview_modules/query-builder-preview-mocks.ts')

    // ui/packages/*/entry.ts
    expect(entries['react-sandbox']).toBe('./ui/packages/react-sandbox/entry.ts')

    // ui/packages/*/standalone-entry.ts
    expect(entries['socket-worker']).toBe('./ui/packages/socket-worker/standalone-entry.ts')
  })

  test('getStandaloneEntryNames', () => {
    const jsEntries = getJSEntryPoints()
    const standaloneEntries = getStandaloneEntryNames(jsEntries)

    expect(standaloneEntries.has('socket-worker')).toBe(true)
    expect(standaloneEntries.has('find-file-worker')).toBe(true)
    expect(standaloneEntries.has('query-builder-preview-mocks')).toBe(true)

    expect(standaloneEntries.has('environment')).toBe(false)
    expect(standaloneEntries.has('react-sandbox')).toBe(false)
  })

  test('getCSSEntryPoints', () => {
    const entries = getCSSEntryPoints()

    // app/assets/stylesheets/variables/themes/*.scss
    expect(entries['dark']).toBe('./app/assets/stylesheets/variables/themes/dark.scss')

    // app/assets/stylesheets/marketing/*.scss
    expect(entries['about']).toBe('./app/assets/stylesheets/marketing/about.scss')

    // app/assets/stylesheets/bundles/*/index.scss
    expect(entries['github']).toBe('./app/assets/stylesheets/bundles/github/index.scss')
  })

  test('getSSREntryPoints', () => {
    const entries = getSSREntryPoints()

    // ui/packages/*/ssr-entry.ts
    expect(entries['react-sandbox']).toBe('./ui/packages/react-sandbox/ssr-entry.ts')

    // app/assets/modules/*/ssr-entry.ts
    expect(entries['react-code-view']).toBe('./app/assets/modules/react-code-view/ssr-entry.ts')

    // app/assets/modules/react-partials/*/ssr-entry.ts
    expect(entries['repos-overview']).toBe('./app/assets/modules/react-partials/repos-overview/ssr-entry.ts')

    // Special case for blackbird-monolith -> blackbird-search
    expect(entries['blackbird-search']).toBe('./app/assets/modules/blackbird-monolith/ssr-entry.ts')
  })
})
