import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {expect, it} from '@github-ui/tests'
import {getIntegrationPermissionSelectorProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

it('Renders integration-permission-selector partial with SSR', async () => {
  const props = getIntegrationPermissionSelectorProps()
  const view = await serverRenderReact({
    name: 'integration-permission-selector',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.exampleMessage)
})
