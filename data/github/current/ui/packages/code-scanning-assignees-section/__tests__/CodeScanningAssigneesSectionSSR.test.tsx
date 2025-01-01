/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCodeScanningAssigneesSectionProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders code-scanning-assignees-section partial with SSR', async () => {
  const props = getCodeScanningAssigneesSectionProps()
  const view = await serverRenderReact({
    name: 'code-scanning-assignees-section',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Assignees')
})
