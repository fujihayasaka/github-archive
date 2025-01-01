/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCopilotFreeUserChecklistProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders copilot-free-user-checklist partial with SSR', async () => {
  const props = getCopilotFreeUserChecklistProps()
  const view = await serverRenderReact({
    name: 'copilot-free-user-checklist',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('copilot-free-user-checklist')
})
