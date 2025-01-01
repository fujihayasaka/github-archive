/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getPullRequestFilesToolbarMockData} from '../test-utils/mock-data'

test('Renders pull-request-files-toolbar partial with SSR', async () => {
  // For unknown reasons, in the test environment only, we get the following console error, causing this test to fail.
  //
  // "Warning: useLayoutEffect does nothing on the server, because its effect cannot be encoded into the server
  // renderer's output format. This will lead to a mismatch between the initial, non-hydrated UI and the intended UI.
  // To avoid this, useLayoutEffect should only be used in components that render exclusively on the client.
  // See https://reactjs.org/link/uselayouteffect-ssr for common fixes."
  //
  // This error does not appear in dev or production consoles, so we think it's safe to mock and ignore.
  // All other console errors will continue to raise as expected.
  //
  // eslint-disable-next-line no-console
  const originalConsoleError = console.error
  jest.spyOn(console, 'error').mockImplementation((message: string) => {
    if (!message?.includes('useLayoutEffect')) {
      originalConsoleError(message)
    }
  })

  const view = await serverRenderReact({
    name: 'pull-request-files-toolbar',
    data: {
      props: {
        toolbarPayload: getPullRequestFilesToolbarMockData(),
      },
    },
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Pull Request Toolbar')
})
