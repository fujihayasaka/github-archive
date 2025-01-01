/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getLaunchCodeProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders launch-code partial with SSR', async () => {
  const props = getLaunchCodeProps()
  const view = await serverRenderReact({
    name: 'launch-code',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Confirm your email address')
})
