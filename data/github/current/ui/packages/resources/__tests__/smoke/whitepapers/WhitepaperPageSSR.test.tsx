/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../../ssr-entry'
import WhitepaperPayload from '../../fixtures/routes/whitepapers/WhitepaperPayload'
import EbookPayload from '../../fixtures/routes/whitepapers/EbookPayload'

test('Renders Whitepaper Page with SSR', async () => {
  const testPayload = WhitepaperPayload
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers/whitepaper-test',
    data: {payload: testPayload},
  })

  // verify the heading.
  expect(view).toMatch('Really Cool Test')

  // verify label text
  expect(view).toMatch('Whitepaper')

  // verify published date
  expect(view).toMatch('November 22, 2024')

  // verify lede
  expect(view).toMatch('Test lede')

  // verify body
  expect(view).toMatch(
    'Eleifend amet donec ligula etiam massa cursus sodales a pharetra posuere suspendisse malesuada.',
  )

  // verify topics
  expect(view).toMatch('AI')
  expect(view).toMatch('DevOps')

  // verify related resources
  expect(view).toMatch('Related Resource 1')
  expect(view).toMatch('Related Resource 2')
  expect(view).toMatch('Related Resource 3')
})

test('Renders Ebook Page with SSR', async () => {
  const testPayload = EbookPayload
  const view = await serverRenderReact({
    name: 'resources',
    path: '/resources/whitepapers/ebook-test',
    data: {payload: testPayload},
  })

  // verify the heading.
  expect(view).toMatch('Really Cool Test')

  // verify label text
  expect(view).toMatch('Ebook')

  // verify published date
  expect(view).toMatch('November 22, 2024')

  // verify lede
  expect(view).toMatch('Test lede')

  // verify body
  expect(view).toMatch(
    'Eleifend amet donec ligula etiam massa cursus sodales a pharetra posuere suspendisse malesuada.',
  )

  // verify topics
  expect(view).toMatch('AI')
  expect(view).toMatch('DevOps')

  // verify related resources
  expect(view).toMatch('Related Resource 1')
  expect(view).toMatch('Related Resource 2')
  expect(view).toMatch('Related Resource 3')

  // verify structured data
  expect(view).toContain(
    '<script type="application/ld+json">{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[{"@type":"ListItem","position":1,"name":"Ebooks & Whitepapers","item":"http://example.invalid/resources/whitepapers"}]}</script>',
  )
  expect(view).toContain(
    '<script type="application/ld+json">{"@context":"https://schema.org","@type":"Article","headline":"Really Cool Test","image":["https://images.ctfassets.net/8aevphvgewt8/51sKKjo7lZqCMeSbzQL87r/26d376e89c527de06e99caacd0fb3add/373369437-53520afb-5cf9-49f1-8f86-4d669567f71b.jpg?w=2560&h=1440&fm=webp","https://images.ctfassets.net/8aevphvgewt8/51sKKjo7lZqCMeSbzQL87r/26d376e89c527de06e99caacd0fb3add/373369437-53520afb-5cf9-49f1-8f86-4d669567f71b.jpg?w=1280&h=960&fm=webp","https://images.ctfassets.net/8aevphvgewt8/51sKKjo7lZqCMeSbzQL87r/26d376e89c527de06e99caacd0fb3add/373369437-53520afb-5cf9-49f1-8f86-4d669567f71b.jpg?w=1000&h=1000&fm=webp"],"publisher":{"@type":"Organization","name":"GitHub","logo":"https://github.githubassets.com/images/modules/open_graph/github-logo.png"},"author":{"@type":"Organization","name":"GitHub","url":"https://www.github.com"}}</script>',
  )
})
