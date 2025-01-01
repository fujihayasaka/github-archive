/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../entry'

test('Renders education-schools-auto-complete partial with SSR', async () => {
  const view = await serverRenderReact({
    name: 'education-schools-auto-complete',
    data: {props: {triggerElementClass: 'school-trigger'}},
  })

  expect(view).toMatch('input type="hidden"')
})
