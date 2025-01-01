/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../../ssr-entry'
import WhitepapersIndexPayload from '../../fixtures/routes/whitepapers/WhitepaperIndexPayload'

test('Renders Whitepaper Category with SSR', async () => {
  const testPayload = WhitepapersIndexPayload
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers',
    data: {payload: testPayload},
  })

  // verify the heading and description.
  expect(view).toMatch('Ebooks &amp; Whitepapers')
  expect(view).toMatch(
    'Lorem ipsum dolor sit amet lorem ipsum dolor sit amet lorem ipsum dolor sit amet lorem ipsum dolor sit amet.',
  )

  // verify card title
  expect(view).toMatch('An introduction to innersource')

  // verify card excerpt
  expect(view).toMatch('Test excerpt')

  // verify card label text
  const whitepaperLabelOccurences = (view.match(/\bWhitepaper\b/g) || []).length
  expect(whitepaperLabelOccurences).toBe(2)

  const ebookLabelOccurences = (view.match(/\bEbook\b/g) || []).length
  expect(ebookLabelOccurences).toBe(2)

  // verify card links link
  const linkOccurences = (view.match(/get-started-with-github-enterprise-cloud/g) || []).length
  expect(linkOccurences).toBe(4)
})
