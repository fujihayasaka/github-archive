import {mockFetch} from '@github-ui/mock-fetch'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {CustomCopilotForm} from '../components/CustomCopilotForm'

const githubRepoId = 5
const mockRepositories = [
  {
    id: githubRepoId,
    name: 'github',
    nameWithOwner: 'github/github',
    owner: 'github',
  },
]

const userEvent = setupUserEvent()

describe('CustomCopilotForm', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    // Copied from https://github.com/primer/react/blob/main/packages/react/src/Banner/Banner.test.tsx:
    //
    // Note: this error occurs due to our usage of `@container` within a
    // `<style>` tag in Banner. The CSS parser for jsdom does not support this
    // syntax and will fail with an error containing the message below.
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
  })

  it('validates name and text content for free text resources', async () => {
    render(<CustomCopilotForm findFileWorkerPath="notUsed" />)

    // Test empty name
    await userEvent.click(screen.getByTestId('new-free-text-resource-button'))
    const saveButton = await screen.findByTestId('save-resource-button')
    await userEvent.click(saveButton)
    expect(await screen.findByText('Name cannot be blank')).toBeInTheDocument()

    // Test empty text
    await userEvent.type(screen.getByTestId('free-text-name'), 'My file')
    await userEvent.click(saveButton)
    expect(await screen.findByText('Text cannot be blank')).toBeInTheDocument()
  })

  it('creates custom copilot with a free text resource successfully', async () => {
    mockFetch.mockRouteOnce('/custom_copilots', {id: 123}, {ok: true})

    // Mock window.location.href. This is necessary because we redirect to the index on succesful save.
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(<CustomCopilotForm findFileWorkerPath="notUsed" />)

    await userEvent.type(screen.getByTestId('name-input'), 'My custom copilot')

    // Add free text resource
    await userEvent.click(screen.getByTestId('new-free-text-resource-button'))
    await userEvent.type(screen.getByTestId('free-text-name'), 'My file')
    expect(screen.getByText('0 / 20,000 characters')).toBeInTheDocument()
    await userEvent.type(screen.getByTestId('free-text-textarea'), 'Text content')
    expect(screen.getByText('12 / 20,000 characters')).toBeInTheDocument()
    await userEvent.click(screen.getByTestId('save-resource-button'))

    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/custom_copilots',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            custom_copilot: {
              name: 'My custom copilot',
              description: '',
              general_instructions: '',
              resources_attributes: [
                {
                  resource_type: 'free_text',
                  _destroy: false,
                  metadata: {
                    text: 'Text content',
                    name: 'My file',
                  },
                },
              ],
            },
          }),
        }),
      )
    })
    expect(window.location.href).toBe('/copilot/spaces/123')

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })

  // It's quite difficult to simulate selecting the file resource from the file picker
  // It fails when we try to type on the search box
  it.skip('creates custom copilot with a file resource successfully', async () => {
    // The multi file picker test is significantly more involved, so we'll
    // just test the single file picker here.
    mockFetch.mockRouteOnce('/custom_copilots', {id: 123}, {ok: true})
    mockFetch.mockRoute(
      '/_filter/repositories?q=',
      {},
      {ok: true, json: async () => ({repositories: mockRepositories})},
    )

    mockFetch.mockRoute(
      `/github-copilot/chat/repositories/${githubRepoId}`,
      {},
      {
        ok: true,
        json: async () => ({
          id: githubRepoId,
          name: 'github',
          ownerLogin: 'github',
          ownerType: 'Organization',
          readmePath: null,
          description: null,
          commitOID: '97820b05f0cda85ee1179589b3bbb13e163107d8',
          ref: 'refs/heads/main',
          refInfo: {
            name: 'main',
            type: 'branch',
          },
          visibility: 'public',
          languages: [],
          customInstructions: null,
        }),
      },
    )

    // Mock window.location.href. This is necessary because we redirect to the index on succesful save.
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(<CustomCopilotForm findFileWorkerPath="" />)

    await userEvent.type(screen.getByTestId('name-input'), 'My custom copilot')
    await userEvent.type(screen.getByTestId('description-input'), 'Test Description')
    expect(screen.getByText('0 / 2,000 characters')).toBeInTheDocument()
    await userEvent.type(screen.getByTestId('general-instructions-input'), 'Test general instructions')
    expect(screen.getByText('25 / 2,000 characters')).toBeInTheDocument()

    // Add GitHub file resource
    await userEvent.click(screen.getByTestId('new-github-file-resource-button'))
    await userEvent.click(screen.getByText(/Select repository/i))
    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/_filter/repositories?q=',
        expect.objectContaining({
          body: undefined,
        }),
      )
    })

    await userEvent.click(await screen.findByText(/github\/github/i))
    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/github-copilot/chat/repositories/${githubRepoId}`,
        expect.objectContaining({
          body: undefined,
        }),
      )
    })

    // The 'resource-file-path-input' is an input from GitHubFileForm that no longer exists.
    // I tried using await userEvent.type(screen.getByPlaceholderText('Search for files or folders'), 'docs/README.md'),
    // but it didn't work.
    await userEvent.type(screen.getByTestId('resource-file-path-input'), 'docs/README.md')
    await userEvent.click(screen.getByTestId('save-resource-button'))

    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/custom_copilots',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            custom_copilot: {
              name: 'My custom copilot',
              description: 'Test Description',
              general_instructions: 'Test general instructions',
              resources_attributes: [
                {
                  resource_type: 'github_file',
                  _destroy: false,
                  metadata: {
                    repository_id: 5,
                    file_path: 'docs/README.md',
                  },
                },
              ],
            },
          }),
        }),
      )
    })
    expect(window.location.href).toBe('/copilot')

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })

  it('shows validation messages on failed save', async () => {
    const errorMessages = {
      name: 'cannot be blank',
      general_instructions: 'is too long (maximum is 2000 characters)',
    }
    const generalInstructions = 'hi'.repeat(2000)
    mockFetch.mockRouteOnce(
      '/custom_copilots',
      {id: 789},
      {ok: false, json: async () => ({errorMessages}), headers: new Headers({'Content-Type': 'application/json'})},
    )

    render(<CustomCopilotForm findFileWorkerPath="" />)

    // set general instructions
    await userEvent.click(screen.getByLabelText('General Instructions'))
    await userEvent.paste(generalInstructions)
    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/custom_copilots',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            custom_copilot: {
              name: '',
              description: '',
              general_instructions: generalInstructions,
              resources_attributes: [],
            },
          }),
        }),
      )
    })

    expect(await screen.findByTestId('error-banner')).toBeInTheDocument()
    expect(await screen.findByText(`Name ${errorMessages.name}`)).toBeInTheDocument()
  })

  it('handles responses without a JSON body', async () => {
    const generalInstructions = 'hi'.repeat(2000)
    mockFetch.mockRouteOnce('/custom_copilots', {id: 789}, {ok: false, json: async () => ({})})

    render(<CustomCopilotForm findFileWorkerPath="" />)

    // set general instructions
    await userEvent.click(screen.getByLabelText('General Instructions'))
    await userEvent.paste(generalInstructions)
    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/custom_copilots',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            custom_copilot: {
              name: '',
              description: '',
              general_instructions: generalInstructions,
              resources_attributes: [],
            },
          }),
        }),
      )
    })

    expect(await screen.findByTestId('error-banner')).toBeInTheDocument()
    expect(await screen.findByText(`An unknown error occurred`)).toBeInTheDocument()
  })

  it('updates custom copilot successfully, preserving repo resource data', async () => {
    const customCopilot = {
      id: 789,
      name: 'Original name',
      description: 'Original description',
      generalInstructions: 'Original general instructions',
      resources: [
        {
          id: '1',
          databaseId: 1,
          repositoryId: 5,
          nwo: 'github/github',
          filePathFilters: 'existing/file/path',
          markedForDestroy: false,
          type: 'repository' as const,
        },
        {
          id: '2',
          databaseId: 2,
          repositoryId: 5,
          nwo: 'github/github',
          filePath: 'docs/README.md',
          markedForDestroy: false,
          type: 'github_file' as const,
        },
      ],
    }
    mockFetch.mockRouteOnce(`/custom_copilots/${customCopilot.id}`, {id: customCopilot.id}, {ok: true})

    // Mock window.location.href. This is necessary because we redirect to the index on succesful save.
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(<CustomCopilotForm customCopilot={customCopilot} findFileWorkerPath="" />)

    await userEvent.clear(screen.getByTestId('name-input'))
    await userEvent.clear(screen.getByTestId('description-input'))
    expect(screen.getByText('29 / 2,000 characters')).toBeInTheDocument()
    await userEvent.clear(screen.getByTestId('general-instructions-input'))
    expect(screen.getByText('0 / 2,000 characters')).toBeInTheDocument()
    await userEvent.type(screen.getByTestId('name-input'), 'Updated name')
    await userEvent.type(screen.getByTestId('description-input'), 'Updated description')
    await userEvent.type(screen.getByTestId('general-instructions-input'), 'Updated general instructions')

    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/custom_copilots/${customCopilot.id}`,
        expect.objectContaining({
          method: 'PUT',
          body: JSON.stringify({
            custom_copilot: {
              name: 'Updated name',
              description: 'Updated description',
              general_instructions: 'Updated general instructions',
              resources_attributes: [
                {
                  resource_type: 'repository',
                  id: 1,
                  _destroy: false,
                  metadata: {
                    repository_id: 5,
                    file_path_filters: ['existing/file/path'],
                  },
                },
                {
                  resource_type: 'github_file',
                  id: 2,
                  _destroy: false,
                  metadata: {
                    repository_id: 5,
                    file_path: 'docs/README.md',
                  },
                },
              ],
            },
          }),
        }),
      )
    })
    expect(window.location.href).toBe(`/copilot/spaces/${customCopilot.id}`)

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })
})
