/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCopilotSweAgentReposPickerProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders copilot-swe-agent-repos-picker partial with SSR', async () => {
  const props = getCopilotSweAgentReposPickerProps()
  const view = await serverRenderReact({
    name: 'copilot-swe-agent-repos-picker',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Repository access')
})
