/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getActionsCustomImagesPolicyProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders actions-custom-images-policy partial with SSR', async () => {
  const props = getActionsCustomImagesPolicyProps()
  const view = await serverRenderReact({
    name: 'actions-custom-images-policy',
    data: {props},
  })

  // verify ssr was able to render something
  expect(view).toBeTruthy()
})
