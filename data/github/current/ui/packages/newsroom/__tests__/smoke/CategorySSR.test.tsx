/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import categoryPagePayload from '../fixtures/CategoryPayload'
import categoryPayloadPage2 from '../fixtures/CategoryPayloadPage2'

test('Renders Newsroom Category Page with SSR', async () => {
  const testPayload = categoryPagePayload
  const view = await serverRenderReact({
    name: 'newsroom',
    path: '/newsroom/press-releases',
    data: {payload: testPayload},
  })

  // verify the hero heading and description.
  expect(view).toMatch('Press releases')
  expect(view).toMatch('The latest and greatest from your friends at GitHub')

  // verify the press release card titles
  const cardTitleOccurences = (view.match(/GitHub Offers Data Residency/g) || []).length
  expect(cardTitleOccurences).toBe(28) // account for data-ref and card title
  expect(view).toMatch('GitHub to Pursue FedRAMP Moderate')

  // verify press release card dates
  const dateOccurences = (view.match(/September 24, 2024/g) || []).length
  expect(dateOccurences).toBe(11)
  expect(view).toMatch('October 18, 2024')
  expect(view).toMatch('October 15, 2024')
  expect(view).toMatch('October 1, 2024')
  expect(view).toMatch('September 27, 2024')

  // verify press release link
  const linkOccurences = (view.match(/Read/g) || []).length
  expect(linkOccurences).toBe(15)

  // verify pagination
  expect(view).toMatch('Previous')
  expect(view).toMatch('aria-label="Page 1"')
  expect(view).toMatch('aria-label="Page 2..."')
  expect(view).toMatch('Next')

  // verify the CTA Banner
  expect(view).toMatch('Get started')
  expect(view).toMatch(
    'Trusted by 90% of the Fortune 100, GitHub helps millions of developers and companies collaborate, build, and deliver secure software faster. And with thousands of DevOps integrations, developers can build smarter with the tools they know from day one—or discover new ones.',
  )
  expect(view).toMatch('Primary action')
  expect(view).toMatch('Secondary action')
})

test('Renders the second Newsroom Category Page', async () => {
  const testPayload = categoryPayloadPage2
  const view = await serverRenderReact({
    name: 'newsroom',
    path: '/newsroom/press-releases?page=2',
    data: {payload: testPayload},
  })

  // verify the hero heading and description.
  expect(view).toMatch('Press releases')
  expect(view).toMatch('The latest and greatest from your friends at GitHub')

  // verify the press release cards
  const dateOccurrences = (view.match(/GitHub Offers Data Residency in the EU with GitHub Enterprise Cloud/g) || [])
    .length
  expect(dateOccurrences).toBe(10) // account for data-ref and card title

  // verify pagination
  expect(view).toMatch('Previous')
  expect(view).toMatch('aria-label="Page 1"')
  expect(view).toMatch('aria-label="Page 2..."')
  expect(view).toMatch('Next')

  // verify the CTA Banner
  expect(view).toMatch('Get started')
  expect(view).toMatch(
    'Trusted by 90% of the Fortune 100, GitHub helps millions of developers and companies collaborate, build, and deliver secure software faster. And with thousands of DevOps integrations, developers can build smarter with the tools they know from day one—or discover new ones.',
  )
  expect(view).toMatch('Primary action')
  expect(view).toMatch('Secondary action')
})
