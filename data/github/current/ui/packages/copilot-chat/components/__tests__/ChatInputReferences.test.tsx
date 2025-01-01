import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen, waitFor, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ChatInput} from '../ChatInput'
import {MenuPortalContainer} from '../PortalContainerUtils'
import {ReferenceToken} from '../ReferenceToken'
import {getChatLinksHandler, getChatReferenceHandlerV2} from './utils/mock-network-calls'

const userEvent = setupUserEvent()

const analyticsMock = http.post('/test_analytics_url', () => HttpResponse.json({status: 200}))
const copilotTokenMock = http.post('/github-copilot/chat/token', () => HttpResponse.json({status: 200}))
const chatCompletionsMock = http.post('/apiURL/chat/completions', () => HttpResponse.json({status: 200, choices: []}))
const githubMock = http.get('/github/*', () => HttpResponse.json({status: 200}))
const githubCopilotMock = http.get('/github-copilot/*', () => HttpResponse.json({status: 200}))
const agentsMock = http.get('/agents', () => [])
const searchMock = http.get('/search/*', () => HttpResponse.json({suggestions: []}))

const server = setupServer(
  getChatLinksHandler(),
  getChatReferenceHandlerV2(),
  analyticsMock,
  githubCopilotMock,
  copilotTokenMock,
  chatCompletionsMock,
  githubMock,
  searchMock,
  agentsMock,
)

// Uncomment if curious or debugging
// server.events.on('request:start', ({request}) => {
//   console.log('MSW intercepted:', request.method, request.url)
// })

beforeAll(() => server.listen())
afterEach(() => {
  server.resetHandlers()
  requests = [] // Clear requests after each test
})
afterAll(() => server.close())

beforeEach(() => {
  // We need to clear the local storage so the textareas are not prepopulated from the previous tests
  localStorage.clear()
})

let requests: Array<{request: Request; requestId: string}> = []

server.events.on('request:start', req => {
  requests.push(req)
})

describe('ChatInput issue references', () => {
  test('Text that contains no references should not be processed', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.type(textArea, 'Hello, world!')

    expect(textArea).toHaveTextContent('Hello, world!')
    expect(preview).toHaveTextContent('Hello, world!')
  })

  test('Text that contains an invalid URL should not be processed', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/copilot')

    expect(textArea).toHaveTextContent('http://localhost/copilot')
    expect(preview).toHaveTextContent('http://localhost/copilot')
  })

  test('Shows Convert to file button', async () => {
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')

    // Suppress warning about nested interactable elements, that is the intentional design of the button.
    const consoleWarnSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    await userEvent.click(textArea)
    await userEvent.paste(codeSnippet)

    const attachmentsToolbar = screen.getByRole('toolbar', {name: /Attachments/i})

    await waitFor(() => {
      const attachments = within(attachmentsToolbar).getAllByRole('button')
      expect(attachments[0]).toHaveTextContent('Convert to file')
    })
    consoleWarnSpy.mockRestore()
  })

  test('Text that contains a valid issue url should make a network call and process the url', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234')
    expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234')

    await waitFor(() => {
      expect(screen.getByText('This is a test issue')).toBeVisible()
    })

    // Test for highlighted issue reference link
    expect(screen.getByText('@github/copilot-chat/issues/1234', {selector: '.mention'})).toBeInTheDocument()

    let foundRequest
    if (copilotFeatureFlags.chatAutocomplete) {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/issue/1234'))
    } else {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/issues/1234'))
    }
    expect(foundRequest).toBeDefined()
  })

  test('Removing an issue chip removes the highlighting from the related issue text', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.type(textArea, 'I want to find this issue: ')
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
    expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')

    await waitFor(() => {
      expect(screen.getByText('This is a test issue')).toBeVisible()
    })

    const issueChip = screen.getByRole('link', {name: 'This is a test issue'})
    act(() => issueChip.focus())
    await userEvent.keyboard('{Backspace}')

    expect(issueChip).not.toBeInTheDocument()
    expect(textArea).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
    expect(preview).toHaveTextContent('I want to find this issue: @github/copilot-chat/issues/1234')
    // Test for removed highlight from issue reference link
    expect(screen.queryByText('@github/copilot-chat/issues/1234', {selector: '.mention'})).not.toBeInTheDocument()
  })

  test('Reverts text when network request fails', async () => {
    if (copilotFeatureFlags.chatAutocomplete) {
      server.use(http.get('/copilot/chat/reference/:owner/:repo/:type/:number', () => HttpResponse.error()))
    } else {
      server.use(http.get('/copilot/chat-links', () => HttpResponse.error()))
    }

    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    await waitFor(() => expect(textArea).toHaveTextContent('http://localhost/github/copilot-chat/issues/1234'))
    expect(preview).toHaveTextContent('http://localhost/github/copilot-chat/issues/1234')

    expect(screen.queryByText('@github/copilot-chat/issues/1234', {selector: '.mention'})).not.toBeInTheDocument()
  })

  test('Issue chip persists when file attachment menu is opened', async () => {
    // Service workers are not available in JSDOM so we need to mock the console.warn
    jest.spyOn(console, 'warn').mockImplementation()

    const {user} = renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <MenuPortalContainer />
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await userEvent.click(screen.getByTestId('copilot-chat-input-textarea'))
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    const attachmentsToolbar = await screen.findByRole('toolbar', {name: /Attachments/i})
    await waitFor(() => {
      const attachments = within(attachmentsToolbar).getAllByRole('link')
      expect(attachments[0]).toHaveTextContent('This is a test issue')
    })

    // Open add attachment menu
    const attachmentButton = screen.getByTestId('attachment-menu-button')
    await userEvent.click(attachmentButton)
    await waitFor(() => {
      expect(screen.getByRole('menu')).toBeInTheDocument()
    })

    // Open the files, folder, and symbols attachment menu
    const filesOption = screen.getByRole('menuitem', {name: /Files, folders, and symbols/i})
    await userEvent.click(filesOption)
    expect(screen.getByRole('dialog', {name: 'Select files, folders, and symbols'})).toBeInTheDocument()

    await user.keyboard('{Escape}')

    // Test the issue chip is still present
    const attachments = within(attachmentsToolbar).getAllByRole('link')
    expect(attachments).toHaveLength(1)
    expect(attachments[0]).toHaveTextContent('This is a test issue')
  })

  test('Duplicate links are processed', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234')
    expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234')

    await waitFor(() => {
      expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234')
    })

    const attachmentsToolbar = screen.getByRole('toolbar', {name: /Attachments/i})
    await waitFor(() => {
      const attachments = within(attachmentsToolbar).getAllByRole('link')
      expect(attachments[0]).toHaveTextContent('This is a test issue')
    })
    let previewRefs = within(preview).getAllByTestId('input-preview-ref')
    expect(previewRefs).toHaveLength(1)

    await userEvent.type(textArea, ' ')
    await userEvent.paste('http://localhost/github/copilot-chat/issues/1234')

    await waitFor(() => {
      expect(preview).toHaveTextContent('@github/copilot-chat/issues/1234 @github/copilot-chat/issues/1234')
    })

    const attachments = within(attachmentsToolbar).getAllByRole('link')
    expect(attachments).toHaveLength(1)
    expect(attachments[0]).toHaveTextContent('This is a test issue')
    previewRefs = within(preview).getAllByTestId('input-preview-ref')
    expect(previewRefs).toHaveLength(2)
    expect(previewRefs[0]).toHaveTextContent('@github/copilot-chat/issues/1234')
    expect(previewRefs[1]).toHaveTextContent('@github/copilot-chat/issues/1234')
  })

  test('Text that contains a reference mention should make a network call and add the reference', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')

    await userEvent.click(textArea)
    await userEvent.paste('summarize this issue: @github/copilot-chat/issues/1234')

    expect(textArea).toHaveTextContent('@github/copilot-chat/issues/1234')

    await waitFor(() => {
      expect(screen.getByText('This is a test issue')).toBeVisible()
    })

    // Test for highlighted issue reference link
    expect(screen.getByText('@github/copilot-chat/issues/1234', {selector: '.mention'})).toBeInTheDocument()

    const foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/issue/1234'))
    expect(foundRequest).toBeDefined()
  })
})

describe('ChatInput pull request references', () => {
  test('Text that contains a valid pull request url should make a network call and process the url', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/pull/1234')

    expect(textArea).toHaveTextContent('@github/copilot-chat/pull/1234')
    expect(preview).toHaveTextContent('@github/copilot-chat/pull/1234')

    await waitFor(() => {
      expect(screen.getByText('This is a test pull request')).toBeVisible()
    })

    // Test for highlighted pull request reference link
    expect(screen.getByText('@github/copilot-chat/pull/1234', {selector: '.mention'})).toBeInTheDocument()

    let foundRequest
    if (copilotFeatureFlags.chatAutocomplete) {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/pull_request/1234'))
    } else {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/pull/1234'))
    }
    expect(foundRequest).toBeDefined()
  })
})

describe('ChatInput discussion references', () => {
  test('Text that contains a valid discussion url should make a network call and process the url', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/discussions/1234')

    expect(textArea).toHaveTextContent('@github/copilot-chat/discussions/1234')
    expect(preview).toHaveTextContent('@github/copilot-chat/discussions/1234')

    await waitFor(() => {
      expect(screen.getByText('This is a test discussion')).toBeVisible()
    })

    // Test for highlighted discussions reference link
    expect(screen.getByText('@github/copilot-chat/discussions/1234', {selector: '.mention'})).toBeInTheDocument()

    let foundRequest
    if (copilotFeatureFlags.chatAutocomplete) {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/discussion/1234'))
    } else {
      foundRequest = requests.find(({request}) => request.url.includes('/github/copilot-chat/discussions/1234'))
    }
    expect(foundRequest).toBeDefined()
  })
})

describe('ChatInput file references', () => {
  test('Pasting a file URL should update the mention reference to exclude the ref', async () => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ChatInput />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const textArea = screen.getByTestId('copilot-chat-input-textarea')
    const preview = screen.getByTestId('copilot-chat-input-textarea-preview')

    await userEvent.click(textArea)
    await userEvent.paste('http://localhost/github/copilot-chat/tree/ref-part-a/ref-part-b/a/b/c/file.text')

    // there is an in-between part where we the mention should be @github/copilot-chat/files/ref-part-a/ref-part-b/a/b/c/file.text,
    // but since that's only present while the request is pending, checking for it would inevitably be flaky

    await waitFor(() => {
      expect(screen.getByText('file.text')).toBeVisible()
    })

    expect(textArea).toHaveTextContent('@github/copilot-chat/files/a/b/c/file.text')
    expect(preview).toHaveTextContent('@github/copilot-chat/files/a/b/c/file.text')

    // Test for highlighted reference mention
    expect(screen.getByText('@github/copilot-chat/files/a/b/c/file.text', {selector: '.mention'})).toBeInTheDocument()
  })
})

describe('ReferenceToken behavior', () => {
  beforeEach(() => {
    window.open = jest.fn() // Mock window.open
  })

  test.each([
    {
      name: 'file reference',
      expectedLink: '/copilot/c/0?reference_id=file-github/copilot-chat@abcdef:src/example.ts',
      reference: {
        type: 'file' as const,
        url: 'http://localhost/src/example.ts',
        path: 'src/example.ts',
        repoID: 1,
        repoOwner: 'github',
        repoName: 'copilot-chat',
        ref: 'main',
        commitOID: 'abcdef',
      },
    },
    {
      name: 'thread-scoped-file reference',
      expectedLink: '/copilot/c/0?reference_id=thread-scoped-file-example.ts',
      reference: {
        type: 'thread-scoped-file' as const,
        name: 'example.ts',
        text: 'const example = "test";',
        language: 'typescript',
      },
    },
  ])('Clicking on a $name opens immersive', async ({reference, expectedLink}) => {
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ReferenceToken reference={reference} onClick={jest.fn()} size="medium" />
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    const referenceToken = screen.getByText('example.ts')
    expect(referenceToken).toBeInTheDocument()

    await userEvent.click(referenceToken)

    expect(window.open).toHaveBeenCalledWith(expectedLink, '_blank')
  })
})

const codeSnippet = `const tokensRef = useRef<Array<HTMLAnchorElement | null>>([])
    const onRemove = (reference: CopilotChatReference, index: number) => {
      const nextFocusTarget = tokensRef.current[index + 1] ?? tokensRef.current[index - 1] ?? returnFocusRef.current
      nextFocusTarget?.focus()

      manager.removeReference(reference)
    }

    const onRemoveAll = () => {
      // setTimeout to delay so we pull focus after the ActionMenu tries to return focus to its (now nonexistent) anchor
      setTimeout(() => returnFocusRef.current?.focus())
      manager.clearCurrentReferences()
    }

    // Scroll to the token that was most recently added
    const prevSelectedReferences = useRef<CopilotChatReference[]>(selectedReferences)
    useLayoutEffect(() => {
      if (prevSelectedReferences.current.length < selectedReferences.length) {
        const newReference = selectedReferences.find(
          reference => !prevSelectedReferences.current.find(prevRef => referencesAreEqual(prevRef, reference)),
        )
        const lastIndex = newReference ? selectedReferences.indexOf(newReference) : -1
        tokensRef?.current?.[lastIndex]?.scrollIntoView({behavior: 'smooth', inline: 'end'})
      }
      prevSelectedReferences.current = selectedReferences
    }, [selectedReferences])

    if (selectedReferences.length === 0 && !isLoading && !showConvertToFileText) return null

    return (
      <div role="toolbar" aria-label="Attachments" className={clsx(className, styles.container)} ref={containerRef}>
        <div
          className={clsx(styles.attachmentsList, scrolledToEnd && styles.scrolledToEnd, isLoading && styles.loading)}
          ref={scrollContainerRef}
        >
          {showConvertToFileText && (
            <div className={styles.convertToFileButton}>
              <Button
                variant="invisible"
                onClick={onConvertToFile}
                leadingVisual={<FileIcon className={styles.convertToFileInternalButton} />}
                className={styles.convertToFileInternalButton}
              >
                Convert to file
              </Button>
              <IconButton variant="invisible" icon={XIcon} aria-label="Remove" tooltipDirection="n" />
            </div>
          )}"`
