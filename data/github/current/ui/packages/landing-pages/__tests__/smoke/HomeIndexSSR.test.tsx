/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

test('Renders HomeIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/home',
    data: {payload: {}},
  })

  // verify Hero
  expect(view).toMatch('Build and ship software')
  expect(view).toMatch('data-hpc')
})
