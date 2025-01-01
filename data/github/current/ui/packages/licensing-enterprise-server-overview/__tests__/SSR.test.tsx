/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getEnterpriseServerOverviewProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders licensing-enterprise-server-overview partial with SSR', async () => {
  const props = getEnterpriseServerOverviewProps()

  const view = await serverRenderReact({
    name: 'licensing-enterprise-server-overview',
    data: {props},
  })

  // verify ssr was able to render content from the props
  expect(view).toMatch('Enterprise Server')
})
