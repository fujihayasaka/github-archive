import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {graphql} from 'react-relay'

import {DuplicateIssuesSection} from '../DuplicateIssuesSection'
import {renderRelay} from '@github-ui/relay-test-utils'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {DuplicateIssuesSectionTestQuery} from './__generated__/DuplicateIssuesSectionTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlag: jest.fn(),
}))
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

const DuplicateIssuesSectionGraphqlTestQuery = graphql`
  query DuplicateIssuesSectionTestQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        ...DuplicateIssuesSectionFragment
      }
    }
  }
`

type DuplicateIssuesSectionQueries = {
  duplicateIssuesSectionQuery: DuplicateIssuesSectionTestQuery
}

const duplicateIssuesSectionRelayMock: RelayMockProps<DuplicateIssuesSectionQueries> = {
  queries: {
    duplicateIssuesSectionQuery: {
      type: 'fragment',
      query: DuplicateIssuesSectionGraphqlTestQuery,
      variables: {
        owner: 'owner',
        repo: 'repo',
        number: 1,
      },
    },
  },
}

describe('DuplicateIssuesSection', () => {
  it('renders', async () => {
    mockUseFeatureFlag.mockReturnValue(true)
    renderRelay<DuplicateIssuesSectionQueries>(
      ({queryData}) => <DuplicateIssuesSection issue={queryData.duplicateIssuesSectionQuery.repository!.issue!} />,
      {
        relay: {
          ...duplicateIssuesSectionRelayMock,
          mockResolvers: {
            Issue: () => ({
              duplicateIssues: {
                nodes: Array(3).fill(undefined),
              },
            }),
          },
        },
        wrapper: Wrapper,
      },
    )

    const section = await screen.findByTestId('duplicate-issues-section')
    expect(within(section).getAllByRole('listitem').length).toBe(3)
  })

  describe('when there are no duplicate issues', () => {
    it('renders with empty state', async () => {
      mockUseFeatureFlag.mockReturnValue(true)
      renderRelay<DuplicateIssuesSectionQueries>(
        ({queryData}) => <DuplicateIssuesSection issue={queryData.duplicateIssuesSectionQuery.repository!.issue!} />,
        {
          relay: {
            ...duplicateIssuesSectionRelayMock,
            mockResolvers: {
              Issue: () => ({
                duplicateIssues: {
                  nodes: [],
                },
              }),
            },
          },
          wrapper: Wrapper,
        },
      )

      const section = await screen.findByTestId('duplicate-issues-section')
      expect(within(section).queryAllByRole('listitem').length).toBe(0)
      expect(within(section).getByText('No related issues found')).toBeVisible()
    })
  })

  describe('when feature flag is off', () => {
    it('does not render', async () => {
      mockUseFeatureFlag.mockReturnValue(false)
      renderRelay<DuplicateIssuesSectionQueries>(
        ({queryData}) => <DuplicateIssuesSection issue={queryData.duplicateIssuesSectionQuery.repository!.issue!} />,
        {
          relay: {
            ...duplicateIssuesSectionRelayMock,
            mockResolvers: {
              Issue: () => ({
                duplicateIssues: {
                  nodes: [],
                },
              }),
            },
          },
          wrapper: Wrapper,
        },
      )

      expect(screen.queryByTestId('duplicate-issues-section')).not.toBeInTheDocument()
    })
  })
})
