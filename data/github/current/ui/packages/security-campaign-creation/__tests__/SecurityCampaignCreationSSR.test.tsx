/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getSecurityCampaignCreationProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders security-campaign-creation partial with SSR', async () => {
  // useNavigate uses useLayoutEffect, which is not supported in SSR. The navigate function is not used in SSR, so
  // this error is safe to ignore in SSR.
  //
  // "Warning: useLayoutEffect does nothing on the server, because its effect cannot be encoded into the server
  // renderer's output format. This will lead to a mismatch between the initial, non-hydrated UI and the intended UI.
  // To avoid this, useLayoutEffect should only be used in components that render exclusively on the client.
  // See https://reactjs.org/link/uselayouteffect-ssr for common fixes."
  //
  // eslint-disable-next-line no-console
  const originalConsoleError = console.error
  jest.spyOn(console, 'error').mockImplementation((message: string) => {
    if (!message?.includes('useLayoutEffect')) {
      originalConsoleError(message)
    }
  })

  const props = getSecurityCampaignCreationProps()

  const view = await serverRenderReact({
    name: 'security-campaign-creation',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Create campaign')
})
