/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCustomSignupContentManagerProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders custom-signup-content-manager partial with SSR', async () => {
  const props = getCustomSignupContentManagerProps()
  const view = await serverRenderReact({
    name: 'custom-signup-content-manager',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.pageTitle)
})
