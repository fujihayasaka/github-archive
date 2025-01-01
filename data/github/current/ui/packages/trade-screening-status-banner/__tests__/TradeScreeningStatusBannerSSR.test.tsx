/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getTradeScreeningStatusBannerProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders trade-screening-status-banner partial with SSR', async () => {
  const props = getTradeScreeningStatusBannerProps()
  const view = await serverRenderReact({
    name: 'trade-screening-status-banner',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.description)
})
