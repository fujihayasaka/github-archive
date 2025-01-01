import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {UseQueryResult} from '@github-ui/react-query'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'

import type {DraftIssue} from '../../content-preview-types'
import {ContentPreviewProvider} from '../../ContentPreviewContext'
import {CreateIssuePreview, type CreateIssuePreviewProps, METADATA_FOOTER_BREAKPOINT} from '../CreateIssuePreview'
import {useAssigneesQuery} from '../use-assignees-query'
import {useRepoQuery} from '../use-repo-query'
import {useTopReposQuery} from '../use-top-repos-query'

jest.mock('react-router-dom', () => ({...jest.requireActual('react-router-dom'), useLocation: jest.fn()}))
jest.mock('../use-repo-query', () => {
  return {
    useRepoQuery: jest.fn().mockRejectedValue({
      isLoading: false,
      data: null,
    }),
  }
})
jest.mock('../use-top-repos-query', () => {
  return {
    useTopReposQuery: jest.fn().mockRejectedValue({
      isLoading: false,
      data: null,
    }),
  }
})
jest.mock('../use-assignees-query', () => ({
  useAssigneesQuery: jest.fn().mockReturnValue({
    isLoading: false,
    data: null,
  }),
}))

const repo = {
  id: 'R_123',
  name: 'repository',
  owner: {login: 'owner'},
  nameWithOwner: 'owner/repository',
  databaseId: 12345,
  hasIssuesEnabled: true,
  viewerIssueCreationPermissions: {
    typeable: false,
  },
  planFeatures: {
    maximumAssignees: 10,
  },
}

const newIssue: DraftIssue = {
  tag: '',
  id: 'new-issue:123#456',
  type: 'new-issue',
  name: 'Issue Title',
  body: 'Issue Description',
  repository: 'orgA/repoA',
  messageId: '123',
  isUserEdited: false,
  assignees: [],
  labels: [],
  projects: [],
}

function setupAndRender({
  issue,
  isPreviewOpening = true,
}: Pick<CreateIssuePreviewProps, 'issue'> & Partial<CreateIssuePreviewProps>) {
  if (!issue) {
    return null
  }

  // Need this otherwise render doesn't work correctly
  renderRelay(
    () => {
      return (
        <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
          <ContentPreviewProvider>
            <CreateIssuePreview issue={issue} isPreviewOpening={isPreviewOpening} onClose={() => {}} />
          </ContentPreviewProvider>
        </CopilotChatProvider>
      )
    },
    {
      relay: {
        queries: {},
        mockResolvers: {},
      },
      wrapper: Wrapper,
    },
  )
}

describe('CreateIssuePreview', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders correctly', async () => {
    jest.mocked(useRepoQuery).mockReturnValue({
      isLoading: false,
      data: repo,
    } as UseQueryResult<RepositoryPickerRepository$data>)
    ;(useTopReposQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: {
        view: {
          topRepositories: {
            edges: [
              {
                node: repo,
              },
            ],
          },
        },
      },
    })

    setupAndRender({issue: newIssue, isPreviewOpening: false})

    expect(await screen.findByText('Create')).toBeInTheDocument()
    expect(await screen.findByRole('link', {name: 'Give feedback'})).toBeInTheDocument()
    expect(await screen.findByText('owner/repository')).toBeInTheDocument()
    expect(await screen.findByDisplayValue('Issue Title', {exact: false})).toBeInTheDocument()
    expect(await screen.findByText('Issue Description')).toBeInTheDocument()
  })

  it('selects the first repo in the Top repos list if no repo is found', async () => {
    ;(useTopReposQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: {
        view: {
          topRepositories: {
            edges: [
              {
                node: repo,
              },
            ],
          },
        },
      },
    })

    setupAndRender({issue: newIssue, isPreviewOpening: false})

    expect(await screen.findByText('Create')).toBeInTheDocument()
    expect(await screen.findByRole('link', {name: 'Give feedback'})).toBeInTheDocument()
    expect(await screen.findByText('owner/repository')).toBeInTheDocument()
    expect(await screen.findByDisplayValue('Issue Title', {exact: false})).toBeInTheDocument()
    expect(await screen.findByText('Issue Description')).toBeInTheDocument()
  })

  it('renders "No repository found." when top repos query fails', () => {
    jest.mocked(useRepoQuery).mockReturnValue({
      isLoading: false,
      data: null,
    } as UseQueryResult<null>)
    ;(useTopReposQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: null,
    })
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: null,
    })

    setupAndRender({issue: newIssue, isPreviewOpening: false})

    expect(screen.getByText('No repositories found.')).toBeInTheDocument()
  })

  it('renders metadata as a sidebar if screen is wide enough', async () => {
    Object.defineProperty(HTMLDivElement.prototype, 'clientWidth', {
      configurable: true,
      value: METADATA_FOOTER_BREAKPOINT,
    })

    jest.mocked(useRepoQuery).mockReturnValue({
      isLoading: false,
      data: repo,
    } as UseQueryResult<RepositoryPickerRepository$data>)
    ;(useTopReposQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: {
        view: {
          topRepositories: {
            edges: [
              {
                node: repo,
              },
            ],
          },
        },
      },
    })

    setupAndRender({issue: newIssue, isPreviewOpening: false})

    expect(await screen.findByText('Create')).toBeInTheDocument()
    const metadataContent = await screen.findAllByTestId('sidebar-section')
    expect(metadataContent.length).toBeGreaterThan(0)
  })

  it('renders metadata as a footer if screen is narrow', async () => {
    Object.defineProperty(HTMLDivElement.prototype, 'clientWidth', {
      configurable: true,
      value: METADATA_FOOTER_BREAKPOINT - 1,
    })

    jest.mocked(useRepoQuery).mockReturnValue({
      isLoading: false,
      data: repo,
    } as UseQueryResult<RepositoryPickerRepository$data>)
    ;(useTopReposQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: {
        view: {
          topRepositories: {
            edges: [
              {
                node: repo,
              },
            ],
          },
        },
      },
    })

    setupAndRender({issue: newIssue, isPreviewOpening: false})

    expect(await screen.findByText('Create')).toBeInTheDocument()
    expect(screen.queryByTestId('sidebar-section')).not.toBeInTheDocument()
  })
})
