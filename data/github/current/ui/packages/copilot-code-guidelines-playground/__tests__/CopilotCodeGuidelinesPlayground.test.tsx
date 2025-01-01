import {mockFetch} from '@github-ui/mock-fetch'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {act, render, screen, waitFor} from '@testing-library/react'
import type {ChangeEvent} from 'react'
import {CopilotCodeGuidelinesPlayground} from '../CopilotCodeGuidelinesPlayground'
import type {CodingGuidelinePath} from '../PlaygroundContext'
//eslint-disable-next-line import/no-nodejs-modules -- we want to mock a fetch response with a ReadableStream
import {ReadableStream} from 'node:stream/web'

jest.mock('@github-ui/code-mirror', () => ({
  __esModule: true,
  // jsdom does not handle CodeMirror's content editable well. Instead we mock CodeMirror to use a regular textarea
  // and pass along the critical arguments like the test id and onChange handler. This way we can test the behavior
  // with jsdom and not have to worry about the content editable behavior.
  default: ({
    value,
    onChange,
    'data-testid': dataTestIdProp,
  }: {
    value: string
    dataTestId: string
    onChange: (value: string) => void
    'data-testid'?: string
  }) => {
    const handleChange = (event: ChangeEvent<HTMLTextAreaElement>) => {
      onChange(event.target.value)
    }
    return <textarea value={value} onChange={handleChange} data-testid={dataTestIdProp} />
  },
}))

const userEvent = setupUserEvent()

describe('CopilotCodeGuidelinesPlayground', () => {
  const defaultProps = {
    indexPath: '/index',
    playgroundRunsPath: '/playground/runs',
    saveCodeGuidelinePath: '/code_guidelines',
    sampleCodeGenerationsPath: '/code_guidelines/sample_code_generations',
    promptCharLimit: 1000,
    codingGuidelinePaths: [] as CodingGuidelinePath[],
    codingGuideline: {
      id: 1,
      name: 'Test Guideline',
      description: 'Test Description',
      exampleCodeViolations: 'Test Violations',
    },
  }

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

  test('renders blankslate when there is no code sample and no code review comments', async () => {
    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    expect(screen.getByTestId('blankslate-container')).toBeInTheDocument()
    expect(screen.getByText('Test your guideline on sample code')).toBeInTheDocument()
    expect(screen.getByTestId('add-sample-code-button')).toBeInTheDocument()
    expect(screen.queryByTestId('sample-container')).not.toBeInTheDocument()
    expect(screen.queryByText('Run when ready...')).not.toBeInTheDocument()

    // When there is no description we remove the option to generate code
    await userEvent.clear(screen.getByTestId('description-input'))
    expect(screen.queryByTestId('add-sample-code-button')).not.toBeInTheDocument()

    // When there is no description we show buttons with sample guidelines that can be accepted
    const sampleGuidelineButton = screen.getAllByTestId('accept-sample-guideline-button')[0]!
    expect(sampleGuidelineButton).toBeInTheDocument()
    await userEvent.click(sampleGuidelineButton)
    await waitFor(() => {
      const descriptionInput = screen.getByTestId('description-input')
      expect((descriptionInput as HTMLTextAreaElement).value.length).toBeGreaterThan(0)
    })
  })

  test('can add sample code and run it to view comments from Copilot', async () => {
    const mockDotcomResponse = {
      references: [
        {type: 'github.pull_request', id: 1},
        {type: 'github.coding_guideline', id: 2},
      ],
      integration: 'copilot-pr-reviews-dev',
      token: 'encrypted-and-encoded-token',
      api: 'https://api.github.com',
    }
    mockFetch.mockRouteOnce(defaultProps.playgroundRunsPath, mockDotcomResponse)

    const mockCAPIResponse = {
      copilot_references: [{type: 'github.generated-pull-request-comment', data: {body: 'Test comment', line: 1}}],
    }

    mockFetch.mockRouteOnce(`${mockDotcomResponse.api}/agents/github-code-review`, undefined, {
      ok: true,
      status: 200,
      //@ts-expect-error - this is a mock response
      body: new ReadableStream<Uint8Array>({
        start(controller) {
          const encoder = new TextEncoder()
          const data = `data: ${JSON.stringify(mockCAPIResponse)}\n\n`

          controller.enqueue(encoder.encode(data))
          controller.close()
        },
      }),
    })

    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    // Add sample code first
    //
    // This act call is necessary to make sure that the lazy loaded CodeMirror component is loaded before we try to use it.
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      await userEvent.click(screen.getByTestId('add-sample-code-button'))
    })
    const codeContent = await screen.findByTestId('sample-content-editor')
    await userEvent.type(codeContent, 'Sample code')

    // Click run button
    await userEvent.click(screen.getByTestId('run-samples-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        defaultProps.playgroundRunsPath,
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({playground: {sample_code: 'Sample code', description: 'Test Description'}}),
        }),
      )
    })

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `${mockDotcomResponse.api}/agents/github-code-review`,
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            Authorization: `GitHub-Bearer ${mockDotcomResponse.token}`,
            'copilot-integration-id': mockDotcomResponse.integration,
            'X-Copilot-Code-Review-Mode': 'eval',
            'Content-Type': 'text/event-stream',
          }),
          body: JSON.stringify({
            messages: [
              {
                role: 'user',
                copilot_references: mockDotcomResponse.references,
              },
            ],
          }),
        }),
      )
    })

    const comment = await screen.findByText('Test comment')
    expect(comment).toBeInTheDocument()
  })

  test('displays error message when saving guideline fails', async () => {
    const errorMessage = 'Failed to save guideline'
    mockFetch.mockRouteOnce(
      defaultProps.saveCodeGuidelinePath,
      {},
      {
        ok: false,
        json: async () => {
          return {errorMessage}
        },
      },
    )

    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    await userEvent.click(screen.getByText('Save guideline'))

    expect(mockFetch.fetch).toHaveBeenCalledWith(
      defaultProps.saveCodeGuidelinePath,
      expect.objectContaining({
        method: 'PUT',
        body: JSON.stringify({
          copilot_coding_guideline: {
            name: defaultProps.codingGuideline.name,
            description: defaultProps.codingGuideline.description,
            example_code_violations: defaultProps.codingGuideline.exampleCodeViolations,
            paths_attributes: [],
          },
        }),
      }),
    )

    expect(await screen.findByTestId('error-banner')).toHaveTextContent(errorMessage)
  })

  test('redirects after successfully saving guideline', async () => {
    mockFetch.mockRouteOnce(defaultProps.saveCodeGuidelinePath, {}, {ok: true})

    // Mock window.location.href
    const originalHref = window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })

    render(
      <CopilotCodeGuidelinesPlayground
        {...defaultProps}
        codingGuidelinePaths={[{id: 1, path: 'foo/bar', markedForDestroy: true}]}
      />,
    )

    await userEvent.click(screen.getByText('Save guideline'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        defaultProps.saveCodeGuidelinePath,
        expect.objectContaining({
          method: 'PUT',
          body: JSON.stringify({
            copilot_coding_guideline: {
              name: defaultProps.codingGuideline.name,
              description: defaultProps.codingGuideline.description,
              example_code_violations: defaultProps.codingGuideline.exampleCodeViolations,
              paths_attributes: [{id: 1, path: 'foo/bar', _destroy: true}],
            },
          }),
        }),
      )
    })

    expect(window.location.href).toBe('/index?flash=updated')

    // Restore original window.location.href
    Object.defineProperty(window, 'location', {
      value: {href: originalHref},
      writable: true,
    })
  })

  test('adding and removing file paths', async () => {
    mockFetch.mockRouteOnce(defaultProps.saveCodeGuidelinePath, {}, {ok: true})

    render(
      <CopilotCodeGuidelinesPlayground
        {...defaultProps}
        codingGuidelinePaths={[{id: 1, path: 'old', markedForDestroy: false}]}
      />,
    )

    expect(screen.queryByTestId('file-path-blankslate')).not.toBeInTheDocument()
    const pathRow = await screen.findByTestId('path-row')
    expect(pathRow).toHaveTextContent('old')

    // Make sure we can remove file paths
    await userEvent.click(screen.getByTestId('remove-file-path-button'))

    // Open the file path modal
    await userEvent.click(screen.getByTestId('open-file-path-modal'))

    // Try to save invalid path
    const filePathInput = await screen.findByTestId('file-path-input')
    await userEvent.type(filePathInput, 'invalid path with spaces')
    await userEvent.click(await screen.findByTestId('add-file-path-button'))
    expect(await screen.findByText('Path cannot contain spaces')).toBeInTheDocument()
    // expect(await screen.findByTestId('file-path-validation-message')).toBeInTheDocument()

    // Save valid file path
    await userEvent.clear(filePathInput)
    await userEvent.type(filePathInput, 'new')
    await userEvent.click(await screen.findByTestId('add-file-path-button'))

    // Make sure new file path is on the page
    expect(screen.queryByTestId('file-path-blankslate')).not.toBeInTheDocument()
    expect(await screen.findByTestId('path-row')).toBeInTheDocument()

    await userEvent.click(screen.getByText('Save guideline'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        defaultProps.saveCodeGuidelinePath,
        expect.objectContaining({
          method: 'PUT',
          body: JSON.stringify({
            copilot_coding_guideline: {
              name: defaultProps.codingGuideline.name,
              description: defaultProps.codingGuideline.description,
              example_code_violations: defaultProps.codingGuideline.exampleCodeViolations,
              paths_attributes: [
                // This path was removed
                {id: 1, path: 'old', _destroy: true},
                // This is the new path that was added from the modal
                {id: null, path: 'new', _destroy: false},
              ],
            },
          }),
        }),
      )
    })
  })

  test('"Undo changes" button behavior', async () => {
    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    const nameInput = screen.getByTestId('name-input')
    await userEvent.clear(nameInput)
    await userEvent.type(nameInput, 'Updated name')

    await waitFor(() => {
      expect(nameInput).toHaveValue('Updated name')
    })

    await userEvent.click(screen.getByTestId('undo-changes-button'))

    await waitFor(() => {
      expect(nameInput).toHaveValue('Test Guideline')
    })
  })

  test('shows an error if description is empty when generating code sample', async () => {
    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    await userEvent.click(screen.getByTestId('add-sample-code-button'))
    await userEvent.clear(screen.getByTestId('description-input'))
    await userEvent.click(screen.getByTestId('generate-sample-code-button'))

    expect(await screen.findByText('Needs a code guideline description to generate code sample')).toBeInTheDocument()
  })

  test('shows an error if the description is too long when generating code sample', async () => {
    const longDescription = 'a'.repeat(defaultProps.promptCharLimit + 1)
    render(
      <CopilotCodeGuidelinesPlayground
        {...defaultProps}
        codingGuideline={{...defaultProps.codingGuideline, description: longDescription}}
      />,
    )

    await userEvent.click(screen.getByTestId('add-sample-code-button'))
    await userEvent.click(screen.getByTestId('generate-sample-code-button'))

    expect(await screen.findByText('Description is too long to generate code sample')).toBeInTheDocument()
  })

  test('calls the code generation endpoint if there is a valid description when generating code sample', async () => {
    const mockGeneratedCode = 'Generated sample code'
    mockFetch.mockRouteOnce(defaultProps.sampleCodeGenerationsPath, {ok: true, sampleCode: mockGeneratedCode})

    render(<CopilotCodeGuidelinesPlayground {...defaultProps} />)

    await userEvent.click(screen.getByTestId('add-sample-code-button'))
    await userEvent.click(screen.getByTestId('generate-sample-code-button'))

    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        defaultProps.sampleCodeGenerationsPath,
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({description: defaultProps.codingGuideline.description}),
        }),
      )
    })

    const codeContent = await screen.findByTestId('sample-content-editor')
    expect(codeContent).toHaveValue(mockGeneratedCode)
  })
})
