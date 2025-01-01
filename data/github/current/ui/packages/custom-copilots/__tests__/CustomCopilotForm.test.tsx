// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {CustomCopilotForm} from '../components/CustomCopilotForm'
import type {GitHubFileFormData} from '../types'
import type {CustomCopilotVisibility} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCustomCopilotMock} from '../test-utils/mock-data'

const createSpacePath = '/copilot/spaces'
jest.mock('../components/MultiFilePicker', () => ({
  MultiFilePicker: ({onSave}: {onSave: (data: GitHubFileFormData[]) => void}) => {
    const mockData: GitHubFileFormData[] = [
      {
        id: 'mock-id',
        type: 'github_file',
        repositoryId: 123,
        nwo: 'mock-org/mock-repo',
        filePath: '/mock/path/file.txt',
      },
    ]

    return (
      <button onClick={() => onSave(mockData)} data-testid="mock-multi-file-picker-save">
        Mock Save
      </button>
    )
  },
}))

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
    mockFetch.mockRouteOnce(createSpacePath, {id: 123, owner: 'test-owner'}, {ok: true})

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
        createSpacePath,
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
    expect(window.location.href).toBe('/copilot/spaces/test-owner/123')

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })

  it('creates custom copilot with a file resource successfully', async () => {
    mockFetch.mockRouteOnce(createSpacePath, {id: 123, owner: 'test-owner'}, {ok: true})

    // Mock window.location.href. This is necessary because we redirect to the index on succesful save.
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(<CustomCopilotForm findFileWorkerPath="" />)

    await userEvent.type(screen.getByTestId('name-input'), 'My custom copilot')
    await userEvent.type(screen.getByTestId('description-input'), 'Test Description')
    expect(screen.getByText('0 / 4,000 characters')).toBeInTheDocument()
    await userEvent.type(screen.getByTestId('general-instructions-input'), 'Test general instructions')
    expect(screen.getByText('25 / 4,000 characters')).toBeInTheDocument()

    const addFileButton = screen.getByText('Add file from a repository')
    await userEvent.click(addFileButton)

    const mockSaveButton = screen.getByTestId('mock-multi-file-picker-save')
    await userEvent.click(mockSaveButton)

    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        createSpacePath,
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
                    repository_id: 123,
                    file_path: '/mock/path/file.txt',
                  },
                },
              ],
            },
          }),
        }),
      )
    })

    expect(window.location.href).toBe('/copilot/spaces/test-owner/123')

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })

  it('shows validation messages on failed save', async () => {
    const errorMessages = {
      name: "can't be blank",
      slug: "can't be blank",
      general_instructions: 'is too long (maximum is 4000 characters)',
    }
    const generalInstructions = 'hi'.repeat(4000)
    mockFetch.mockRouteOnce(
      createSpacePath,
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
        createSpacePath,
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
    expect(await screen.findByText(`General instructions ${errorMessages.general_instructions}`)).toBeInTheDocument()
  })

  it('shows validation messages on failed save if only the slug is taken', async () => {
    const errorMessages = {
      slug: 'has already been taken',
    }

    mockFetch.mockRouteOnce(
      '/copilot/spaces',
      {id: 789},
      {ok: false, json: async () => ({errorMessages}), headers: new Headers({'Content-Type': 'application/json'})},
    )

    render(<CustomCopilotForm findFileWorkerPath="" />)
    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/copilot/spaces',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({
            custom_copilot: {
              name: '',
              description: '',
              general_instructions: '',
              resources_attributes: [],
            },
          }),
        }),
      )
    })

    expect(await screen.findByTestId('error-banner')).toBeInTheDocument()
    expect(
      await screen.findByText(
        'The name of this space is too close to another existing space. Please modify the name and try again.',
      ),
    ).toBeInTheDocument()
  })

  it('handles responses without a JSON body', async () => {
    const generalInstructions = 'hi'.repeat(2000)
    mockFetch.mockRouteOnce(createSpacePath, {id: 789}, {ok: false, json: async () => ({})})

    render(<CustomCopilotForm findFileWorkerPath="" />)

    // set general instructions
    await userEvent.click(screen.getByLabelText('General Instructions'))
    await userEvent.paste(generalInstructions)
    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        createSpacePath,
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
    const customCopilot = getCustomCopilotMock({
      id: 789,
      oldId: 789,
      owner: undefined,
      name: 'Original name',
      description: 'Original description',
      generalInstructions: 'Original general instructions',
      slug: 'copilot-slug',
      updatedAt: '',
      slugWithOwner: 'copilot-owner/copilot-slug',
      ownerAvatar: 'https://github.com/monalisa.png',
      ownerDisplayName: 'monalisa',
      visibility: 'private' as CustomCopilotVisibility,
      sizePercentage: 2,
      ownerIsOrg: false,
      resources: [
        {
          id: '2',
          databaseId: 2,
          repositoryId: 5,
          nwo: 'github/github',
          filePath: 'docs/README.md',
          sizePercentage: 2,
          fileExists: true,
          markedForDestroy: false,
          type: 'github_file' as const,
          commitish: 'main',
        },
      ],
    })
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
    expect(screen.getByText('29 / 4,000 characters')).toBeInTheDocument()
    await userEvent.clear(screen.getByTestId('general-instructions-input'))
    expect(screen.getByText('0 / 4,000 characters')).toBeInTheDocument()
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

  it('updates custom copilot with owner successfully, preserving repo resource data', async () => {
    const customCopilot = getCustomCopilotMock({
      id: 789,
      oldId: 789,
      name: 'Original name',
      description: 'Original description',
      generalInstructions: 'Original general instructions',
      slug: 'copilot-slug',
      owner: 'copilot-owner',
      updatedAt: '',
      slugWithOwner: 'copilot-owner/copilot-slug',
      ownerAvatar: 'https://github.com/monalisa.png',
      ownerDisplayName: 'monalisa',
      visibility: 'private' as CustomCopilotVisibility,
      sizePercentage: 2,
      ownerIsOrg: false,
      resources: [
        {
          id: '2',
          databaseId: 2,
          repositoryId: 5,
          nwo: 'github/github',
          filePath: 'docs/README.md',
          sizePercentage: 2,
          fileExists: true,
          markedForDestroy: false,
          type: 'github_file' as const,
          commitish: 'main',
        },
      ],
    })

    mockFetch.mockRouteOnce(
      `/copilot/spaces/${customCopilot.owner}/${customCopilot.id}`,
      {id: customCopilot.id},
      {ok: true},
    )

    // Mock window.location.href. This is necessary because we redirect to the index on succesful save.
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(<CustomCopilotForm customCopilot={customCopilot} findFileWorkerPath="" />)

    await userEvent.clear(screen.getByTestId('name-input'))
    await userEvent.clear(screen.getByTestId('description-input'))
    expect(screen.getByText('29 / 4,000 characters')).toBeInTheDocument()
    await userEvent.clear(screen.getByTestId('general-instructions-input'))
    expect(screen.getByText('0 / 4,000 characters')).toBeInTheDocument()
    await userEvent.type(screen.getByTestId('name-input'), 'Updated name')
    await userEvent.type(screen.getByTestId('description-input'), 'Updated description')
    await userEvent.type(screen.getByTestId('general-instructions-input'), 'Updated general instructions')

    await userEvent.click(screen.getByTestId('save-custom-copilot-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/copilot/spaces/${customCopilot.owner}/${customCopilot.id}`,
        expect.objectContaining({
          method: 'PUT',
          body: JSON.stringify({
            custom_copilot: {
              name: 'Updated name',
              description: 'Updated description',
              general_instructions: 'Updated general instructions',
              resources_attributes: [
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
