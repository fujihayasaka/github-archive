import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen} from '@testing-library/react'
import {graphql} from 'relay-runtime'

import {IssueBodyHeaderActions} from '../IssueBodyHeaderActions'
import type {IssueBodyHeaderActionsTestQuery} from './__generated__/IssueBodyHeaderActionsTestQuery.graphql'

const mockUseFeatureFlags = jest.fn().mockReturnValue({})
jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlags: () => mockUseFeatureFlags({}),
}))

beforeEach(() => {
  mockUseFeatureFlags.mockClear()
})

describe('IssueBodyHeaderActions', () => {
  it('does not show "Find relevant files" link when the feature flag is disabled', async () => {
    setup()

    const actionsButton = screen.getByRole('button', {name: 'Issue body actions'})
    act(() => {
      actionsButton.click()
    })

    // Verify that the "Find relevant files" option is not visible
    expect(screen.queryByText('Find relevant files')).not.toBeInTheDocument()
  })

  it('shows "Find relevant files" link when the feature flag is enabled', async () => {
    setup({copilot_find_relevant_files: true})

    const actionsButton = screen.getByRole('button', {name: 'Issue body actions'})
    act(() => {
      actionsButton.click()
    })

    // Verify that the "Find relevant files" option is visible
    expect(screen.getByText('Find relevant files')).toBeInTheDocument()
  })
})

const setup = (
  {copilot_find_relevant_files}: {copilot_find_relevant_files: boolean} = {copilot_find_relevant_files: false},
) => {
  mockUseFeatureFlags.mockReturnValue({
    copilot_find_relevant_files,
  })

  const startIssueBodyEdit = jest.fn()
  const {relayMockEnvironment} = renderRelay<{issueBodyHeaderActions: IssueBodyHeaderActionsTestQuery}>(
    ({queryData}) => (
      <IssueBodyHeaderActions
        issue={queryData.issueBodyHeaderActions.repository!.issue}
        author={queryData.issueBodyHeaderActions.repository!.issue!.author!}
        comment={queryData.issueBodyHeaderActions.repository!.issue!}
        viewerCanUpdate
        startIssueBodyEdit={startIssueBodyEdit}
        url="https://github.com/owner/repo/issues/1"
        copilotApiUrl="https://copilot.github.com/api"
      />
    ),
    {
      relay: {
        queries: {
          issueBodyHeaderActions: {
            type: 'fragment',
            query: graphql`
              query IssueBodyHeaderActionsTestQuery @relay_test_operation {
                repository(owner: "owner", name: "repo") {
                  issue(number: 33) {
                    # eslint-disable-next-line relay/unused-fields
                    ...IssueBodyHeaderActions_issue
                    # eslint-disable-next-line relay/unused-fields
                    ...IssueBodyHeaderActions_comment
                    # eslint-disable-next-line relay/unused-fields
                    author {
                      ...IssueBodyHeaderActions
                    }
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              title: 'Test Issue',
              body: 'Test body content',
              author: {login: 'monalisa', id: 'MDQ6VXNlcjEyMzQ1Ng=='},
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  return {
    relayMockEnvironment,
    startIssueBodyEdit,
  }
}
