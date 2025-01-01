import {screen} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, useFragment} from 'react-relay'
import {mockClientEnv} from '@github-ui/client-env/mock'
import {IssueSidebar} from '../IssueSidebar'
import type {IssueSidebarTestQuery} from './__generated__/IssueSidebarTestQuery.graphql'
import type {IssueViewerViewer$key} from '../__generated__/IssueViewerViewer.graphql'
import {issueViewerViewerFragment} from '../IssueViewer'
import {BUTTON_LABELS} from '../../constants/buttons'
import {noop} from '@github-ui/noop'
import type {IssueSidebarLazyTestQuery} from './__generated__/IssueSidebarLazyTestQuery.graphql'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'

const optionConfig = {
  singleKeyShortcutsEnabled: true,
  navigate: noop,
}

beforeEach(() => {
  jest.clearAllMocks()
})

// eslint-disable-next-line @typescript-eslint/no-unused-expressions
graphql`
  query IssueSidebarLazyTestQuery @relay_test_operation {
    node(id: "test-id") {
      ...IssueSidebarLazySections @arguments(customisedNotificationsEnabled: true)
    }
  }
`

function renderTestComponent({viewerCanType = true, withViewer = true, mockResolversOverrides = {}} = {}) {
  return renderRelay<{
    sidebarQuery: IssueSidebarTestQuery
    lazySidebarQuery: IssueSidebarLazyTestQuery
  }>(
    ({queryData}) => {
      mockClientEnv({
        login: withViewer ? 'monalisa' : undefined,
      })
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, queryData.sidebarQuery.viewer)

      return (
        <IssueSidebar
          sidebarKey={queryData.sidebarQuery.node!}
          viewer={withViewer ? viewer : null}
          optionConfig={optionConfig}
        />
      )
    },
    {
      relay: {
        queries: {
          sidebarQuery: {
            type: 'fragment',
            query: graphql`
              query IssueSidebarTestQuery @relay_test_operation {
                node(id: "test-id") {
                  ... on Issue {
                    ...IssueSidebarPrimaryQuery
                  }
                }
                viewer {
                  ...IssueViewerViewer
                }
              }
            `,
            variables: {},
          },
          lazySidebarQuery: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Issue() {
            return {
              viewerCanType,
              projectItemsNext: {
                edges: [],
              },
            }
          },
          Repository() {
            return {
              issueTypes: [
                {
                  name: 'Bug',
                },
              ],
            }
          },
          Project() {
            // a bit hacky, but needed to not get a coalition error
            return {
              name: 'test',
              title: 'test',
            }
          },
          ...mockResolversOverrides,
        },
      },
      wrapper: Wrapper,
    },
  )
}

describe('rendering', () => {
  test('renders metadata for issue viewer for a logged in user', () => {
    renderTestComponent()

    expect(screen.getByText('Assignees')).toBeInTheDocument()
    expect(screen.getByText('Labels')).toBeInTheDocument()
    expect(screen.getByText('Projects')).toBeInTheDocument()
    expect(screen.getByText('Milestone')).toBeInTheDocument()
    expect(screen.getByText('Development')).toBeInTheDocument()
    expect(screen.getByText('Type')).toBeInTheDocument()
  })

  test('renders metadata for issue viewer for a logged out users', () => {
    renderTestComponent({withViewer: false})

    expect(screen.getByText('Assignees')).toBeInTheDocument()
    expect(screen.getByText('Labels')).toBeInTheDocument()
    expect(screen.getByText('Projects')).toBeInTheDocument()
    expect(screen.getByText('Milestone')).toBeInTheDocument()
    expect(screen.getByText('Development')).toBeInTheDocument()
    expect(screen.getByText('Type')).toBeInTheDocument()
  })

  test('does not render the Notifications section for a logged out user', () => {
    renderTestComponent({withViewer: false})

    expect(screen.queryByText('Notifications')).not.toBeInTheDocument()
  })

  test('does render the Notifications section for a logged in user', () => {
    renderTestComponent()

    expect(screen.getByText('Notifications')).toBeInTheDocument()
  })
})

describe('hotkeys', () => {
  test('opening issue type dialog', async () => {
    const user = setupUserEvent()
    renderTestComponent({withViewer: true})

    expect(screen.queryByText(BUTTON_LABELS.selectType)).not.toBeInTheDocument()

    await user.keyboard('t')

    expect(screen.getByText(BUTTON_LABELS.selectType)).toBeInTheDocument()
  })
})

describe('graceful degradation', () => {
  test('renders Projects fallback when no projectItemsNext are returned', () => {
    // Suppress console.error which we rethrow in the error boundary
    jest.spyOn(console, 'error').mockImplementation()

    renderTestComponent({
      withViewer: false,
      mockResolversOverrides: {
        Issue() {
          return {viewerCanType: true, projectItemsNext: null}
        },
      },
    })

    expect(screen.getByText('Projects are currently unavailable')).toBeInTheDocument()
  })
})
