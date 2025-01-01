/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../../ssr-entry'
import WhitePaperPage from '../../fixtures/routes/whitepapers/WhitepaperDetailsPayload'

test('Renders Whitepaper Confirmation with SSR', async () => {
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers/test-whitepaper/confirmation',
    data: {payload: WhitePaperPage},
  })
  expect(view).toMatch('Whitepaper Test')
})
