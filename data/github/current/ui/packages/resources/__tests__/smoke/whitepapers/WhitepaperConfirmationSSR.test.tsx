/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../../ssr-entry'
import WhitepaperPayload from '../../fixtures/routes/whitepapers/WhitepaperPayload'
import Whitepaper2Payload from '../../fixtures/routes/whitepapers/Whitepaper2Payload'

test('Renders Whitepaper Confirmation with SSR', async () => {
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers/test-whitepaper/confirmation',
    data: {payload: WhitepaperPayload},
  })

  // verify the heading.
  expect(view).toMatch('Really Cool Test')

  // verify related resources
  expect(view).toMatch('Related Resource 1')
  expect(view).toMatch('Related Resource 2')
  expect(view).toMatch('Related Resource 3')

  // verify description without asset provided
  expect(view).toMatch('An email has been sent to you with the PDF.')
})

test('Renders Whitepaper Confirmation with downloadable asset url', async () => {
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers/test-whitepaper/confirmation',
    data: {payload: Whitepaper2Payload},
  })

  // verify the heading.
  expect(view).toMatch('Really Cool Test')

  // verify related resources
  expect(view).toMatch('Related Resource 1')
  expect(view).toMatch('Related Resource 2')
  expect(view).toMatch('Related Resource 3')

  // verify description with asset provided
  expect(view).toMatch('Check your email to get the link or download it here:')

  // verify download button
  expect(view).toMatch('Download PDF')
})
