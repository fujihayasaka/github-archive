import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen, waitFor} from '@testing-library/react'
import {FirstTimeContributionBanner} from '../FirstTimeContributionBanner'
import {graphql} from 'react-relay'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {FirstTimeContributionBannerTestQuery} from './__generated__/FirstTimeContributionBannerTestQuery.graphql'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'

import {MockPayloadGenerator} from 'relay-test-utils'
import {OPEN_SOURCE_GUIDE_URL} from '../../../constants/links'
import type {FirstTimeContributionBannerContributingGuidelinesQuery} from '../__generated__/FirstTimeContributionBannerContributingGuidelinesQuery.graphql'
import FIRST_TIME_CONTRIBUTION_BANNER_CONTRIBUTING_GUIDELINES_GRAPHQL_QUERY from '../__generated__/FirstTimeContributionBannerContributingGuidelinesQuery.graphql'

const id = mockRelayId()
const firstTimeContributionLink = 'https://github.com/github/github/blob/main/CONTRIBUTING.md'

const setup = (overrides = {}, resolveSecondary = true) => {
  return renderRelay<{
    firstTimeContributionBannerQuery: FirstTimeContributionBannerTestQuery
    secondaryQuery: FirstTimeContributionBannerContributingGuidelinesQuery
  }>(
    ({queryData}) => (
      <FirstTimeContributionBanner repository={queryData.firstTimeContributionBannerQuery.repository!} />
    ),
    {
      relay: {
        queries: {
          firstTimeContributionBannerQuery: {
            type: 'fragment',
            query: graphql`
              query FirstTimeContributionBannerTestQuery @relay_test_operation {
                repository(owner: "github", name: "github") {
                  ...FirstTimeContributionBanner
                }
              }
            `,
            variables: {},
          },
          secondaryQuery: {
            type: 'preloaded',
            query: FIRST_TIME_CONTRIBUTION_BANNER_CONTRIBUTING_GUIDELINES_GRAPHQL_QUERY,
            // a bit hacky, but resolving for some other node instead allows us
            // to easily test the skeleton state
            variables: {node: resolveSecondary ? id : 'mock-id'},
          },
        },
        mockResolvers: {
          Repository() {
            return {
              id,
              showFirstTimeContributorBanner: true,
              nameWithOwner: 'github/github',
              contributingGuidelines: {
                firstTimeContributionLink,
              },
              communityProfile: {
                goodFirstIssueIssuesCount: 1,
              },
              url: 'https://github.com/github/github',
              ...overrides,
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}

test('it does not render if the server says so', async () => {
  setup({showFirstTimeContributorBanner: false})
  await waitFor(() => expect(screen.queryByText('Want to contribute', {exact: false})).not.toBeInTheDocument())
})

test('initially renders with link to OS guidelines', async () => {
  setup({}, false)
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  const link = screen.getByTestId('contributing-guidelines')
  expect(link).toBeVisible()
  expect(link).toHaveAttribute('href', OPEN_SOURCE_GUIDE_URL)
})

test('it shows banner with link to repo contributing guidelines', async () => {
  setup()
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  const link = screen.getByTestId('contributing-guidelines')
  expect(link).toBeVisible()
  expect(link).toHaveAttribute('href', firstTimeContributionLink)
})

test('it shows banner with link to open source contributing guide as fallback', async () => {
  setup({contributingGuidelines: null})
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  const link = screen.getByTestId('contributing-guidelines')
  expect(link).toBeVisible()
  expect(link).toHaveAttribute('href', OPEN_SOURCE_GUIDE_URL)
})

test('has link to good first issues', async () => {
  setup()
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  expect(screen.getByTestId('repo-good-first-issues')).toBeVisible()
})

test('does not have link to good first issues if none available', async () => {
  setup({communityProfile: {goodFirstIssueIssuesCount: 0}})
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  expect(screen.queryByTestId('repo-good-first-issues')).not.toBeInTheDocument()
})

test('dismiss for this repo', async () => {
  const {relayMockEnvironment, user} = setup()
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  await user.click(screen.getByRole('button', {name: 'Dismiss'}))
  expect(screen.getByRole('menuitem', {name: 'Dismiss for this repository only'})).toBeVisible()
  await user.click(screen.getByRole('menuitem', {name: 'Dismiss for this repository only'}))

  act(() => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('dismissFirstTimeContributionBannerForRepoMutation')
      return MockPayloadGenerator.generate(operation, {})
    })
  })

  await waitFor(() => expect(screen.queryByText('Want to contribute', {exact: false})).not.toBeInTheDocument())
})

test('dismiss for all repos', async () => {
  const {relayMockEnvironment, user} = setup()
  expect(await screen.findByText('Want to contribute', {exact: false})).toBeVisible()
  await user.click(screen.getByRole('button', {name: 'Dismiss'}))
  expect(screen.getByRole('menuitem', {name: 'Dismiss for this repository only'})).toBeVisible()
  await user.click(screen.getByRole('menuitem', {name: 'Dismiss for all repositories'}))

  act(() => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('dismissFirstTimeContributionBannerMutation')
      return MockPayloadGenerator.generate(operation, {})
    })
  })

  await waitFor(() => expect(screen.queryByText('Want to contribute', {exact: false})).not.toBeInTheDocument())
})
