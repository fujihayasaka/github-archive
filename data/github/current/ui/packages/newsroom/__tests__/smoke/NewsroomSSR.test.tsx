/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import homePagePayload from '../fixtures/HomePayload'
test('Renders Newsroom Homepage with SSR', async () => {
  const testPayload = homePagePayload
  const view = await serverRenderReact({
    name: 'newsroom',
    path: '/newsroom',
    data: {payload: testPayload},
  })

  // verify the hero title
  expect(view).toMatch('GitHub Newsroom')

  // verify the hero primary CTA
  expect(view).toMatch('Contact Sales')

  // verify the hero secondary CTA
  expect(view).toMatch('Contact Press')

  // verify hero statistics headers
  expect(view).toMatch('100M+')
  expect(view).toMatch('90%')
  expect(view).toMatch('4M+')

  // verify hero statistic descriptions
  expect(view).toMatch('Developers')
  expect(view).toMatch('Fortune 100')
  expect(view).toMatch('Organizations')

  // verify the newsroom press release heading
  expect(view).toMatch('Press releases')

  // verify the newsroom press release cards
  expect(view).toMatch('Scaling accessibility within GitHub and beyond')
  expect(view).toMatch('Explore Github')
  expect(view).toMatch('Media Kit')

  // verify the newsroom reports heading
  expect(view).toMatch('Reports')

  // verify the newsroom report cards
  expect(view).toMatch('The 2022 Total Economic Impact™ Driving')
  expect(view).toMatch('Newsroom report card 2')
  expect(view).toMatch('Newsroom report card 3')

  // verify report card statistics
  expect(view).toMatch('Copilot by the numbers')
  expect(view).toMatch('1.8M+')
  expect(view).toMatch('77K+')
  expect(view).toMatch('500K+')

  // verify report card statistic descriptions
  expect(view).toMatch('paid Copilot users')
  expect(view).toMatch('77,000+ organizations have adopted GitHub Copilot')
  expect(view).toMatch('maintainers, students, and teachers using Copilot for free')

  // verify the In the news heading
  expect(view).toMatch('In the news')

  // verify the In the news cards
  expect(view).toMatch('GitHub improves supply chain security with general availability of Artifact Attestations')
  expect(view).toMatch('SD Times / July 26, 2024')
  expect(view).toMatch('In the news card 2')
  expect(view).toMatch('In the news card 2 description ')
  expect(view).toMatch('In the news card 3')
  expect(view).toMatch('In the news card 3 description')

  // verify the newsroom Customer stories heading
  expect(view).toMatch('Customer stories')

  // verify the newsroom Customer stories cards
  expect(view).toMatch('With 12,000 developers using GitHub Copilot, Accenture doubles down on GitHub’s platform.')
  expect(view).toMatch('Newsroom Homepage - Featured Story 2')
  expect(view).toMatch('Newsroom Homepage - Featured Story 3')

  // verify the newsroom Customer stories card CTA text
  expect(view).toMatch('Read story')

  // verify CTA Section Heading
  expect(view).toMatch('Over 100 million developers call GitHub home')

  // verify CTA Section Cards
  expect(view).toMatch('Explore Github')
  expect(view).toMatch('Media Kit')

  // verify CTA Section Card Description
  expect(view).toMatch(
    'What is GitHub, it need to be explained in a few lines to entice people to click on this lovely little card',
  )

  // verify CTA Section Heading
  expect(view).toMatch('Get started')

  // verify CTA Section Description
  expect(view).toMatch(
    'GitHub is the world’s leading AI-powered developer platform to build, scale, and deliver secure software. Over 100 million people, including more than 90% of the Fortune 100 companies, use GitHub to collaborate and experiment across 420+ million repositories.',
  )

  // verify CTA Primary Button
  expect(view).toMatch('Primary action')

  // verify CTA Secondary Button
  expect(view).toMatch('Secondary action')
})
