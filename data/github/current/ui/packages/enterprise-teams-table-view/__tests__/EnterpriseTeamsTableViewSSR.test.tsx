/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getEnterpriseTeamsTableViewProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders enterprise-teams-table-view partial with SSR', async () => {
  // useSearchParams uses useLayoutEffect, which is not supported in SSR. This error does not appear in dev or
  // production consoles, so we think it's safe to mock and ignore.
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

  const props = getEnterpriseTeamsTableViewProps()

  const view = await serverRenderReact({
    name: 'enterprise-teams-table-view',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.business_slug)
})
