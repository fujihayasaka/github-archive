import {renderRelay} from '@github-ui/relay-test-utils'
import type {InternalIssueNewPageUrlArgumentsMetadataQuery} from '../issue-new/__generated__/InternalIssueNewPageUrlArgumentsMetadataQuery.graphql'
import ISSUE_NEW_QUERY from '../issue-new/__generated__/InternalIssueNewPageUrlArgumentsMetadataQuery.graphql'
import {screen} from '@testing-library/react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {MemoryRouter} from 'react-router-dom'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {InternalIssueNewPageWithUrlParams} from '../issue-new/InternalIssueNewPage'
import safeStorage from '@github-ui/safe-storage'

type defaultArgs = {
  assigneeLogins: string
  labelNames: string
  milestoneTitle: string
  type: string
  projectNumbers: number[]
  withTriagePermission: boolean
  discussionNumber: number
  templateFilter: string
}

const DEFAULT_QUERY_ARGS: defaultArgs = {
  assigneeLogins: '',
  labelNames: '',
  milestoneTitle: '',
  type: '',
  projectNumbers: [],
  withTriagePermission: false,
  discussionNumber: 0,
  templateFilter: '',
}
jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

function setup({queryArgs = DEFAULT_QUERY_ARGS, search = '', mockResolvers = {}}) {
  mockedUseAppPayload.mockReturnValue({
    scoped_repository: {id: 1},
    current_user: {
      avatarUrl: '',
      login: 'monalisa',
    },
  })

  return renderRelay<{
    pageQuery: InternalIssueNewPageUrlArgumentsMetadataQuery
  }>(
    ({queryRefs: {pageQuery}}) => (
      <MemoryRouter
        future={{v7_relativeSplatPath: true, v7_startTransition: true}}
        initialEntries={[{pathname: '/', search}]}
      >
        <AnalyticsProvider appName="issue-create" category="" metadata={{}}>
          <InternalIssueNewPageWithUrlParams urlParameterQueryData={pageQuery} />
        </AnalyticsProvider>
      </MemoryRouter>
    ),
    {
      relay: {
        queries: {
          pageQuery: {
            type: 'preloaded',
            query: ISSUE_NEW_QUERY,
            variables: {
              ...queryArgs,
              withAssignees: queryArgs.assigneeLogins !== '',
              withLabels: queryArgs.labelNames !== '',
              withMilestone: queryArgs.milestoneTitle !== '',
              withType: queryArgs.type !== '',
              withProjects: queryArgs.projectNumbers.length > 0,
              includeDiscussion: queryArgs.discussionNumber > 0,
              withTemplate: queryArgs.templateFilter !== '',
              name: 'some',
              owner: 'owner',
            },
          },
        },
        mockResolvers: {
          ...mockResolvers,
        },
      },
    },
  )
}

describe('InternalIssueNewPage', () => {
  test('presets milestone when URL contains ?milestone=masterplan', async () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        milestoneTitle: 'masterplan',
      },

      mockResolvers: {
        Milestone() {
          return {
            title: 'masterplan',
            progressPercentage: 0,
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              milestoneable: true,
            },
          }
        },
      },
    })

    expect(await screen.findByText('masterplan')).toBeInTheDocument()
  })
  test('sets single label when URL contains ?labels=bug', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        labelNames: 'bug',
      },
      mockResolvers: {
        Label() {
          return {
            name: 'bug',
            nameHTML: 'bug',
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              labelable: true,
            },
          }
        },
      },
    })
    const labelSection = screen.getByTestId('issue-labels')
    expect(labelSection).toBeInTheDocument()

    expect(screen.getByText('bug')).toBeInTheDocument()
  })

  test('sets multiple labels when URL contains ?labels=bug,enhancement', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        labelNames: 'bug',
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              labelable: true,
            },
            labels: {
              nodes: [
                {
                  name: 'bug',
                  nameHTML: 'bug',
                },
                {
                  name: 'enhancement',
                  nameHTML: 'enhancement',
                },
              ],
            },
          }
        },
      },
    })
    const labelSection = screen.getByTestId('issue-labels')
    expect(labelSection).toBeInTheDocument()

    expect(screen.getByText('bug')).toBeInTheDocument()
    expect(screen.getByText('enhancement')).toBeInTheDocument()
  })

  test('sets single assignee when URL contains ?assignees=octocat', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        assigneeLogins: 'octocat',
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              assignable: true,
            },
            assignableUsers: {
              nodes: [
                {
                  login: 'octocat',
                },
              ],
            },
          }
        },
      },
    })

    expect(screen.getByText('octocat')).toBeInTheDocument()
  })
  test('sets multiple assignees when URL contains ?assignees=octocat,hubot', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        assigneeLogins: 'octocat,hubot',
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              assignable: true,
            },
            assignableUsers: {
              nodes: [
                {
                  login: 'octocat',
                },
                {
                  login: 'hubot',
                },
              ],
            },
          }
        },
      },
    })

    expect(screen.getByText('octocat')).toBeInTheDocument()
    expect(screen.getByText('hubot')).toBeInTheDocument()
  })
  test('sets single project when URL contains ?projects=octo-org/1', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        projectNumbers: [1],
        withTriagePermission: true,
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              triageable: true,
            },
            owner: {
              projectsV2ByNumber: {
                nodes: [
                  {
                    title: 'sprint',
                    number: 1,
                  },
                ],
              },
            },
          }
        },
      },
    })
    expect(screen.getByText('sprint')).toBeInTheDocument()
  })
  test('sets multiple projects when URL contains ?projects=octo-org/1,octo-org/2', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        projectNumbers: [1, 2],
        withTriagePermission: true,
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              triageable: true,
            },
            owner: {
              projectsV2ByNumber: {
                nodes: [
                  {
                    title: 'sprint',
                    number: 1,
                  },
                  {
                    title: 'nextsprint',
                    number: 2,
                  },
                ],
              },
            },
          }
        },
      },
    })
    expect(screen.getByText('sprint')).toBeInTheDocument()
    expect(screen.getByText('nextsprint')).toBeInTheDocument()
  })

  test('sets issue type when URL contains ?type=bug', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        type: 'bug',
        withTriagePermission: true,
      },
      mockResolvers: {
        IssueType() {
          return {
            name: 'bug',
            isEnabled: true,
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              typeable: true,
              triageable: true,
            },
          }
        },
      },
    })
    expect(screen.getByText('bug')).toBeInTheDocument()
  })

  test('presets values when URL contains ?created_from_discussion_number=1', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        discussionNumber: 37,
      },
      mockResolvers: {
        Label() {
          return {
            name: 'bug',
            nameHTML: 'bug',
          }
        },
        Discussion() {
          return {
            title: 'random',
            number: 37,
            formattedBody: '123123',
          }
        },
      },
    })
    expect(screen.getByText('bug')).toBeInTheDocument()
    expect(screen.getByLabelText('Add a title')).toHaveValue('random')
    expect(screen.getByText('123123')).toBeInTheDocument()
  })

  test('applies template when URL contains ?template=myTemplate.yml', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        templateFilter: 'myTemplate.yml',
      },
      search: '?template=myTemplate.yml',
      mockResolvers: {
        IssueTemplate() {
          return {
            title: 'templateTitle',
            body: 'templateBody',
            labels: {
              edges: [
                {
                  node: {
                    name: 'failure',
                    nameHTML: 'failure',
                  },
                },
              ],
            },
            assignees: {
              edges: [
                {
                  node: {
                    login: 'octocat',
                  },
                },
              ],
            },
            type: {
              name: 'bug',
              isEnabled: true,
            },
          }
        },
        Repository() {
          return {
            issueForm: undefined,
          }
        },
      },
    })
    expect(screen.getByText('templateBody')).toBeInTheDocument()
    expect(screen.getByLabelText('Add a title')).toHaveValue('templateTitle')
    expect(screen.getByText('octocat')).toBeInTheDocument()
    expect(screen.getByText('failure')).toBeInTheDocument()
    expect(screen.getByText('bug')).toBeInTheDocument()
  })

  test('sets title when URL contains ?title=superman', () => {
    setup({
      queryArgs: DEFAULT_QUERY_ARGS,
      search: '?title=superman',
      mockResolvers: {},
    })
    expect(screen.getByLabelText('Add a title')).toHaveValue('superman')
  })

  test('sets title when URL contains ?body=wonderwomen', () => {
    setup({
      queryArgs: DEFAULT_QUERY_ARGS,
      search: '?body=wonderwomen',
      mockResolvers: {},
    })
    expect(screen.getByText('wonderwomen')).toBeInTheDocument()
  })

  test('Convert from discussion takes precedence from url with title=...', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        discussionNumber: 37,
      },
      search: '?title=superman',
      mockResolvers: {
        Discussion() {
          return {
            title: 'random',
            number: 37,
          }
        },
      },
    })
    expect(screen.getByLabelText('Add a title')).toHaveValue('random')
  })

  test('url params take precedence over template', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        templateFilter: 'myTemplate.yml',
      },
      search: '?template=myTemplate.yml&title=urlTitle',
      mockResolvers: {
        IssueTemplate() {
          return {
            title: 'templateTitle',
          }
        },
        Repository() {
          return {
            issueForm: undefined,
          }
        },
      },
    })
    expect(screen.getByLabelText('Add a title')).toHaveValue('urlTitle')
  })

  test('local storage takes precedence over url', () => {
    const safeLocalStorage = safeStorage('sessionStorage')
    const title = 'spiderman'
    safeLocalStorage.setItem(`github-issues.BLANK_ISSUE.create-issue-title`, JSON.stringify(title))

    setup({
      queryArgs: DEFAULT_QUERY_ARGS,
      search: '?title=superman',
      mockResolvers: {
        Repository() {
          return {
            name: 'issues',
            owner: {
              login: 'github',
            },
          }
        },
      },
    })
    expect(screen.getByLabelText('Add a title')).toHaveValue(title)
  })

  test('local storage data is not shared between templates', () => {
    const safeLocalStorage = safeStorage('sessionStorage')
    const title = 'spiderman'
    safeLocalStorage.setItem('github-issues.BLANK_ISSUE.create-issue-title', JSON.stringify(title))
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        templateFilter: 'myTemplate.yml',
      },
      search: '?template=myTemplate.yml',
      mockResolvers: {
        IssueTemplate() {
          return {
            title: 'templateTitle',
            filename: 'myTemplate.yml',
          }
        },
        Repository() {
          return {
            issueForm: undefined,
          }
        },
      },
    })
    expect(screen.getByLabelText('Add a title')).toHaveValue('templateTitle')
  })

  test('Does not set milestone when user has no milestoneable permissions', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        milestoneTitle: 'masterplan',
      },

      mockResolvers: {
        Milestone() {
          return {
            title: 'masterplan',
            progressPercentage: 0,
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              milestoneable: false,
            },
          }
        },
      },
    })

    expect(screen.queryByText('masterplan')).not.toBeInTheDocument()
  })

  test('Does not set labels when user has no labelable permissions', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        labelNames: 'bug',
      },
      mockResolvers: {
        Label() {
          return {
            name: 'bug',
            nameHTML: 'bug',
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              labelable: false,
            },
          }
        },
      },
    })

    expect(screen.queryByText('bug')).not.toBeInTheDocument()
  })

  test('Does not set assignees when user has no assignable permissions', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        assigneeLogins: 'octocat',
      },
      mockResolvers: {
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              assignable: false,
            },
            assignableUsers: {
              nodes: [
                {
                  login: 'octocat',
                },
              ],
            },
          }
        },
      },
    })

    expect(screen.queryByText('octocat')).not.toBeInTheDocument()
  })

  test('Does not set type when user has no typeable permissions', () => {
    setup({
      queryArgs: {
        ...DEFAULT_QUERY_ARGS,
        type: 'bug',
        withTriagePermission: true,
      },
      mockResolvers: {
        IssueType() {
          return {
            name: 'bug',
            isEnabled: true,
          }
        },
        Repository() {
          return {
            viewerIssueCreationPermissions: {
              typeable: false,
              triageable: true,
            },
          }
        },
      },
    })
    expect(screen.queryByText('bug')).not.toBeInTheDocument()
  })
})
