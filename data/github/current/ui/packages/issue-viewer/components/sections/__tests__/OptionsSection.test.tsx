import {screen} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import type {
  OptionsSectionTestQuery,
  OptionsSectionTestQuery$data,
} from './__generated__/OptionsSectionTestQuery.graphql'
import {ISSUE_VIEWER_DEFAULT_CONFIG, type OptionConfig} from '../../OptionConfig'
import {OptionsSection} from '../OptionsSection'
import {BUTTON_LABELS} from '../../../constants/buttons'
import {LABELS} from '../../../constants/labels'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {IssueSidebarPrimaryGraphqlQuery} from '../../IssueSidebar'
import {useFragment} from 'react-relay'
import type {IssueSidebarPrimaryQuery$key} from '../../__generated__/IssueSidebarPrimaryQuery.graphql'

const query = graphql`
  query OptionsSectionTestQuery @relay_test_operation {
    node(id: "test-id") {
      ... on Issue {
        ...IssueSidebarPrimaryQuery @dangerously_unaliased_fixme
      }
    }
  }
`

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

test('Renders h2 heading', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanUpdateNext: true,
            viewerCanDelete: false,
            viewerCanTransfer: false,
            viewerCanPinIssues: false,
            viewerCanConvertToDiscussion: false,
            viewerCanType: false,
          }
        },
      },
    },
  })

  expect(screen.getByRole('heading', {level: 2, name: LABELS.optionsTitle})).toBeInTheDocument()
})

test('Does render pin option when viewer can pin issues to the repository', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            repository: {
              viewerCanPinIssues: true,
            },
          }
        },
      },
    },
  })

  expect(screen.getByText(BUTTON_LABELS.pinIssue)).toBeInTheDocument()
})

test('Does not render pin option when viewer cannot pin issues to the repository', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            repository: {
              viewerCanPinIssues: false,
            },
          }
        },
      },
    },
  })

  expect(screen.queryByText(BUTTON_LABELS.pinIssue)).not.toBeInTheDocument()
})

it('Does render transfer issue', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanUpdateNext: true,
            viewerCanDelete: false,
            viewerCanTransfer: true,
          }
        },
      },
    },
  })

  expect(screen.getByText('Transfer issue')).toBeInTheDocument()
})

it('Does not render issue transfer button if the user cannot update but can delete current repo', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanUpdateNext: true,
            viewerCanDelete: true,
            viewerCanTransfer: false,
          }
        },
      },
    },
  })

  expect(screen.queryByText('Transfer issue')).not.toBeInTheDocument()
})

test('Does not render delete button if the user cannot delete but can update current repo', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanUpdateNext: true,
            viewerCanDelete: false,
            viewerCanTransfer: true,
          }
        },
      },
    },
  })

  expect(screen.getByText('Transfer issue')).toBeInTheDocument()
  expect(screen.queryByText('Delete permanently')).not.toBeInTheDocument()
})

test('Renders h2 heading for screen reader navigation', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanUpdateNext: true,
            viewerCanDelete: false,
            viewerCanTransfer: true,
          }
        },
      },
    },
  })

  expect(screen.getByRole('heading', {level: 2, name: LABELS.optionsTitle})).toBeInTheDocument()
})

test('Does not render the `Convert to discussion` button when the viewer is not authorized to convert', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanConvertToDiscussion: false,
          }
        },
      },
    },
  })

  expect(screen.queryByText(BUTTON_LABELS.convertToDiscussion)).not.toBeInTheDocument()
})

test('Renders the `Convert to discussion` button when the viewer is authorized to convert', () => {
  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(({queryData: {issue}}) => <TestComponent optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'issue1',
            viewerCanConvertToDiscussion: true,
          }
        },
      },
    },
  })

  expect(screen.getByText(BUTTON_LABELS.convertToDiscussion)).toBeInTheDocument()
})

test('Renders the duplicate issue button if the user can update current repo and has FF enabled', () => {
  mockUseFeatureFlag.mockReturnValue(true)

  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(
    ({queryData: {issue}}) => (
      <TestComponent optionConfig={{...ISSUE_VIEWER_DEFAULT_CONFIG, showIssueCreateButton: true}} issue={issue} />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              id: 'issue1',
              viewerCanUpdateNext: true,
            }
          },
        },
      },
    },
  )

  expect(screen.getByText('Duplicate issue')).toBeInTheDocument()
})

test('Does not render duplicate issue button if the user cannot update current repo', () => {
  mockUseFeatureFlag.mockReturnValue(true)

  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(
    ({queryData: {issue}}) => (
      <TestComponent optionConfig={{...ISSUE_VIEWER_DEFAULT_CONFIG, showIssueCreateButton: true}} issue={issue} />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              id: 'issue1',
              viewerCanUpdateNext: false,
            }
          },
        },
      },
    },
  )

  expect(screen.queryByText('Duplicate issue')).not.toBeInTheDocument()
})

test('Does not render duplicate issue button if the FF `issues_react_duplicate_issue` is disabled', () => {
  mockUseFeatureFlag.mockReturnValue(false)

  renderRelay<{
    issue: OptionsSectionTestQuery
  }>(
    ({queryData: {issue}}) => (
      <TestComponent optionConfig={{...ISSUE_VIEWER_DEFAULT_CONFIG, showIssueCreateButton: true}} issue={issue} />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              id: 'issue1',
              viewerCanUpdateNext: true,
            }
          },
        },
      },
    },
  )

  expect(screen.queryByText('Duplicate issue')).not.toBeInTheDocument()
})

type TestComponentProps = {
  issue: OptionsSectionTestQuery$data
  optionConfig?: OptionConfig
}

function TestComponent({issue, optionConfig}: TestComponentProps) {
  const issueKey = useFragment<IssueSidebarPrimaryQuery$key>(IssueSidebarPrimaryGraphqlQuery, issue.node)

  if (!issueKey) return null
  return <OptionsSection optionConfig={optionConfig ?? ISSUE_VIEWER_DEFAULT_CONFIG} issue={issueKey} />
}
