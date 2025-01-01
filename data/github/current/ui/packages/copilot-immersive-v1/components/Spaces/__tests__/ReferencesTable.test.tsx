import type {
  CustomCopilotFreeTextResource,
  CustomCopilotGitHubFileResource,
  CustomCopilotGitHubIssueResource,
  CustomCopilotGitHubPullRequestResource,
  CustomCopilotUploadedTextFileResource,
} from '@github-ui/custom-copilots/types'
import {mockFetch} from '@github-ui/mock-fetch'
import {render as htmlRender, setupUserEvent, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {ThemeProvider} from '@primer/react'
import {render, screen} from '@testing-library/react'

import {ReferencesTable} from '../ReferencesTable'

const userEvent = setupUserEvent()

describe('ReferencesTable', () => {
  let githubFileResource: CustomCopilotGitHubFileResource
  let freeTextFileResource: CustomCopilotFreeTextResource
  let githubIssueResource: CustomCopilotGitHubIssueResource
  let githubPullRequestResource: CustomCopilotGitHubPullRequestResource
  let uploadedTextFileResource: CustomCopilotUploadedTextFileResource
  let onUpdateResourceMock: jest.Mock
  let onDeleteResourceMock: jest.Mock

  beforeEach(() => {
    githubFileResource = {
      id: '11',
      databaseId: 11,
      repositoryId: 4,
      nwo: 'monalisa/smile',
      filePath: 'test/integration/sample_controller_test.rb',
      sizePercentage: 0.6854166667,
      markedForDestroy: false,
      fileExists: true,
      type: 'github_file',
      commitish: 'main',
    }

    freeTextFileResource = {
      id: '12',
      databaseId: 12,
      text: 'foo',
      name: 'free-text-info',
      sizePercentage: 0.0027777778,
      markedForDestroy: false,
      type: 'free_text',
    }

    githubIssueResource = {
      id: '13',
      databaseId: 13,
      markedForDestroy: false,
      type: 'github_issue',
      nwo: 'monalisa/smile',
      number: 1,
      sizePercentage: 0.004,
      title: 'Issue Title',
      url: 'github.com/monalisa/smile/issues/1',
      repositoryId: 4,
    }

    githubPullRequestResource = {
      id: '14',
      databaseId: 14,
      markedForDestroy: false,
      type: 'github_pull_request',
      nwo: 'monalisa/smile',
      number: 3,
      sizePercentage: 0.03,
      title: 'Pull Request Title',
      url: 'github.com/monalisa/smile/pull/3',
      repositoryId: 4,
    }

    uploadedTextFileResource = {
      id: '15',
      type: 'uploaded_text_file',
      name: 'uploaded-document.txt',
      copilotChatAttachmentId: 123,
      markedForDestroy: false,
      sizePercentage: 0.05,
    }

    onUpdateResourceMock = jest.fn()
    onDeleteResourceMock = jest.fn()
  })

  describe('CustomCopilotGitHubFileResource', () => {
    test('displays correctly', () => {
      render(
        <ReferencesTable
          resources={[githubFileResource]}
          onDeleteResource={onDeleteResourceMock}
          onUpdateResource={onUpdateResourceMock}
        />,
      )

      const path = githubFileResource.filePath.split('/')
      const fileName = path.pop() as string
      const filePath = [githubFileResource.nwo, ...path].join('/')

      expect(screen.getByText(filePath)).toBeInTheDocument()
      expect(screen.getByText(fileName)).toBeInTheDocument()
    })

    test('cannot edit', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubFileResource.filePath}`))
      expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    })

    test('can delete', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubFileResource.filePath}`))
      await userEvent.click(screen.getByRole('menuitem', {name: 'Delete'}))

      expect(onDeleteResourceMock).toHaveBeenLastCalledWith(githubFileResource)
    })
  })

  describe('CustomCopilotFreeTextResource', () => {
    test('displays correctly', () => {
      render(
        <ReferencesTable
          resources={[freeTextFileResource]}
          onDeleteResource={onDeleteResourceMock}
          onUpdateResource={onUpdateResourceMock}
        />,
      )

      expect(screen.getByText(freeTextFileResource.name)).toBeInTheDocument()
    })
    test('can edit', async () => {
      const mockResponse = {[freeTextFileResource.id]: 0.1234}
      mockFetch.mockRouteOnce('/copilot/spaces/resource_sizes', mockResponse)

      htmlRender(
        <ThemeProvider>
          <ReferencesTable
            resources={[freeTextFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
        {wrapper: withBaseProvidersWrapper(), appPayload: {copilotSpacesConfig: {maxContentSize: 100}}},
      )
      await userEvent.click(screen.getByLabelText(`Attachment actions: ${freeTextFileResource.name}`))
      await userEvent.click(screen.getByText('Edit'))
      await userEvent.clear(screen.getByPlaceholderText('Give the file a title'))
      await userEvent.type(screen.getByPlaceholderText('Give the file a title'), 'new file name')
      await userEvent.click(screen.getByText('Add'))

      expect(onUpdateResourceMock).toHaveBeenLastCalledWith({
        ...freeTextFileResource,
        name: 'new file name',
        sizePercentage: 0.1234,
      })

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/copilot/spaces/resource_sizes',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            resources: [
              {
                id: freeTextFileResource.id,
                // eslint-disable-next-line camelcase
                resource_type: 'free_text',
                metadata: {text: 'foo', name: 'new file name'},
              },
            ],
          }),
        }),
      )
    })

    test('can delete', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[freeTextFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${freeTextFileResource.name}`))
      await userEvent.click(screen.getByRole('menuitem', {name: 'Delete'}))

      expect(onDeleteResourceMock).toHaveBeenLastCalledWith(freeTextFileResource)
    })
  })

  describe('CustomCopilotGitHubIssueResource', () => {
    test('displays correctly', () => {
      render(
        <ReferencesTable
          resources={[githubIssueResource]}
          onDeleteResource={onDeleteResourceMock}
          onUpdateResource={onUpdateResourceMock}
        />,
      )

      expect(screen.getByText(githubIssueResource.title)).toBeInTheDocument()
      expect(screen.getByText(githubIssueResource.nwo)).toBeInTheDocument()
      const issueLink = screen.getByRole('link', {name: `${githubIssueResource.title} #${githubIssueResource.number}`})
      expect(issueLink).toHaveAttribute('href', githubIssueResource.url)
    })

    test('cannot edit', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubIssueResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubIssueResource.title}`))
      expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    })

    test('can delete', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubIssueResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubIssueResource.title}`))
      await userEvent.click(screen.getByRole('menuitem', {name: 'Delete'}))

      expect(onDeleteResourceMock).toHaveBeenLastCalledWith(githubIssueResource)
    })
  })

  describe('CustomCopilotGitHubPullRequestResource', () => {
    test('displays correctly', () => {
      render(
        <ReferencesTable
          resources={[githubPullRequestResource]}
          onDeleteResource={onDeleteResourceMock}
          onUpdateResource={onUpdateResourceMock}
        />,
      )

      expect(screen.getByText(githubPullRequestResource.title)).toBeInTheDocument()
      expect(screen.getByText(githubPullRequestResource.nwo)).toBeInTheDocument()
      const pullRequestLink = screen.getByRole('link', {
        name: `${githubPullRequestResource.title} #${githubPullRequestResource.number}`,
      })
      expect(pullRequestLink).toHaveAttribute('href', githubPullRequestResource.url)
    })

    test('cannot edit', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubPullRequestResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubPullRequestResource.title}`))
      expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    })

    test('can delete', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[githubPullRequestResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText(`Attachment actions: ${githubPullRequestResource.title}`))
      await userEvent.click(screen.getByRole('menuitem', {name: 'Delete'}))

      expect(onDeleteResourceMock).toHaveBeenLastCalledWith(githubPullRequestResource)
    })
  })

  describe('CustomCopilotUploadedTextFileResource', () => {
    test('displays correctly', () => {
      render(
        <ReferencesTable
          resources={[uploadedTextFileResource]}
          onDeleteResource={onDeleteResourceMock}
          onUpdateResource={onUpdateResourceMock}
        />,
      )

      expect(screen.getByText(uploadedTextFileResource.name)).toBeInTheDocument()
    })

    test('cannot edit', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[uploadedTextFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText('Resource actions'))
      expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    })

    test('can delete', async () => {
      render(
        <ThemeProvider>
          <ReferencesTable
            resources={[uploadedTextFileResource]}
            onDeleteResource={onDeleteResourceMock}
            onUpdateResource={onUpdateResourceMock}
          />
        </ThemeProvider>,
      )

      await userEvent.click(screen.getByLabelText('Resource actions'))
      await userEvent.click(screen.getByRole('menuitem', {name: 'Delete'}))

      expect(onDeleteResourceMock).toHaveBeenLastCalledWith(uploadedTextFileResource)
    })
  })
})
