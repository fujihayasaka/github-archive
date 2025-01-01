/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getLicensingAdvancedSecurityOverviewProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders licensing-advanced-security-overview partial with SSR', async () => {
  const props = getLicensingAdvancedSecurityOverviewProps()
  const view = await serverRenderReact({
    name: 'licensing-advanced-security-overview',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Advanced Security')
})
