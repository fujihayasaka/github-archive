import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'

import {FileStreamEventType, FileStreamParser, generateIteration} from '../generate-iteration'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-helpers', () => ({
  makeCAPIRequest: jest.fn(),
}))

describe('FileStreamParser', () => {
  let parser: FileStreamParser
  let onEventMock: jest.Mock

  beforeEach(() => {
    parser = new FileStreamParser()
    onEventMock = jest.fn()
  })

  it('should emit NEW_FILE and FILE_CONTENT_CHUNK events for valid file content', () => {
    const chunk = '<<—[file1.txt]\nHello, World!\n—>>\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, 'stop')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Hello, World!\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Hello, World!'}],
      finishReason: 'stop',
    })
  })

  it('should handle multiple files in a single chunk', () => {
    const chunk = '<<—[file1.txt]\nContent1\n—>>\n<<—[file2.txt]\nContent2\n—>>\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, 'stop')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Content1\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file2.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file2.txt',
      chunk: 'Content2\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file2.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [
        {fileName: 'file1.txt', content: 'Content1'},
        {fileName: 'file2.txt', content: 'Content2'},
      ],
      finishReason: 'stop',
    })
  })

  it('should handle incomplete chunks and finalize correctly', () => {
    parser.processChunk('<<—[file1.txt]\nPartial content', onEventMock)
    parser.processChunk(' continued\n—>>\n', onEventMock)
    parser.finalize(onEventMock, 'stop')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Partial content continued\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Partial content continued'}],
      finishReason: 'stop',
    })
  })

  it('should emit COMPLETE event with isPartial set to true when a file is not completed before stream ends', () => {
    // Process a partial file that doesn't get closed
    parser.processChunk('<<—[unclosed-file.js]\nconst data = {\n  unfinished: true,\n', onEventMock)

    // Finalize without sending the end marker for the file
    parser.finalize(onEventMock, 'stop')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'unclosed-file.js',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'unclosed-file.js',
      chunk: 'const data = {\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'unclosed-file.js',
      chunk: '  unfinished: true,\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'unclosed-file.js',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'unclosed-file.js', content: 'const data = {\n  unfinished: true,'}],
      finishReason: 'stop',
      isPartial: true,
    })
  })

  it('should emit PROMPT_FILTERED and FILTER_EXPLANATION_CHUNK events for filtered content', () => {
    const chunk = '<<—[file1.txt]\nPartial content\n[[[filtered]]]\nExplanation line 1\nExplanation line 2\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, 'content_filter')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Partial content\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.PROMPT_FILTERED,
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'Explanation line 1\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'Explanation line 2\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Partial content'}],
      finishReason: 'content_filter',
    })
  })

  it('should emit FILTER_SUGGESTION events for filter suggestions', () => {
    const chunk =
      '[[[filtered]]]\nExplanation text\n[[[filter_suggestion_start]]]\nTry this alternative prompt\ninstead of the filtered one.\n[[[filter_suggestion_end]]]\nMore explanation\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, 'content_filter')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.PROMPT_FILTERED,
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'Explanation text\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_SUGGESTION,
      suggestion: 'Try this alternative prompt\ninstead of the filtered one.',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'More explanation\n',
    })
  })

  it('should handle multiple filter suggestions', () => {
    const chunk =
      '[[[filtered]]]\n[[[filter_suggestion_start]]]\nFirst suggestion\n[[[filter_suggestion_end]]]\n[[[filter_suggestion_start]]]\nSecond suggestion\n[[[filter_suggestion_end]]]\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, 'content_filter')

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.PROMPT_FILTERED,
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_SUGGESTION,
      suggestion: 'First suggestion',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_SUGGESTION,
      suggestion: 'Second suggestion',
    })
  })

  it('should handle complex filter scenario with explanations and suggestions', () => {
    // Process multiple chunks to test the streaming nature
    parser.processChunk('[[[filtered]]]\nYour prompt was filtered because', onEventMock)
    parser.processChunk(' it contains inappropriate content.\n', onEventMock)
    parser.processChunk('[[[filter_suggestion_start]]]\n', onEventMock)
    parser.processChunk('Try using more appropriate language\n', onEventMock)
    parser.processChunk('[[[filter_suggestion_end]]]\n', onEventMock)
    parser.processChunk('Here is more explanation about our content policy.\n', onEventMock)
    parser.processChunk(
      '[[[filter_suggestion_start]]]\nConsider a different approach\n[[[filter_suggestion_end]]]\n',
      onEventMock,
    )
    parser.finalize(onEventMock, 'content_filter')

    // Verify the PROMPT_FILTERED event was emitted
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.PROMPT_FILTERED,
    })

    // Verify explanation chunks were emitted
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'Your prompt was filtered because it contains inappropriate content.\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
      chunk: 'Here is more explanation about our content policy.\n',
    })

    // Verify suggestion events were emitted
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_SUGGESTION,
      suggestion: 'Try using more appropriate language',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILTER_SUGGESTION,
      suggestion: 'Consider a different approach',
    })

    // Verify the complete event is emitted at the end
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [],
      finishReason: 'content_filter',
    })
  })

  it('should handle undefined finishReason when finalizing', () => {
    const chunk = '<<—[file1.txt]\nSome content\n—>>\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock, undefined)

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Some content\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Some content'}],
      // No finishReason included in the event
    })
  })
})

describe('generateIteration', () => {
  it('should emit CONTENT_FILTERED event when finish_reason is content_filter', async () => {
    const onEventMock = jest.fn()
    const encoder = new TextEncoder()
    const mockReader = {
      read: jest
        .fn()
        .mockResolvedValueOnce({
          value: encoder.encode(
            `${JSON.stringify({
              choices: [
                {
                  delta: {content: 'Test content'},
                  finish_reason: 'content_filter',
                },
              ],
            })}\n\n`,
          ),
          done: false,
        })
        .mockResolvedValueOnce({done: true}),
    }

    ;(makeCAPIRequest as jest.Mock).mockImplementation(async () => ({
      ok: true,
      body: {
        getReader: () => mockReader,
      },
    }))

    await generateIteration({
      prompt: 'Test prompt',
      generationType: 'generate',
      editorState: {files: {}},
      refinementHistory: [],
      apiURL: 'https://api.example.com',
      authTokenProvider: {
        getAuthToken: async () => new AuthToken('valid-token', '2023-10-01T00:00:00Z', []),
      } as CopilotAuthTokenProvider,
      onEvent: onEventMock,
    })

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.CONTENT_FILTERED,
      filteredCategories: undefined,
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [],
      finishReason: 'content_filter',
    })
  })

  it('should emit CONTENT_FILTERED event with filtered categories and severities', async () => {
    const onEventMock = jest.fn()
    const encoder = new TextEncoder()
    const mockReader = {
      read: jest
        .fn()
        .mockResolvedValueOnce({
          value: encoder.encode(
            `${JSON.stringify({
              choices: [
                {
                  delta: {content: 'Test content'},
                  finish_reason: 'content_filter',
                  content_filter_results: {
                    hate: {filtered: false, severity: '0'},
                    self_harm: {filtered: true, severity: '2'},
                    sexual: {filtered: false, severity: '0'},
                    violence: {filtered: true, severity: '1'},
                  },
                },
              ],
            })}\n\n`,
          ),
          done: false,
        })
        .mockResolvedValueOnce({done: true}),
    }

    ;(makeCAPIRequest as jest.Mock).mockImplementation(async () => ({
      ok: true,
      body: {
        getReader: () => mockReader,
      },
    }))

    await generateIteration({
      prompt: 'Test prompt',
      generationType: 'generate',
      editorState: {files: {}},
      refinementHistory: [],
      apiURL: 'https://api.example.com',
      authTokenProvider: {
        getAuthToken: async () => new AuthToken('valid-token', '2023-10-01T00:00:00Z', []),
      } as CopilotAuthTokenProvider,
      onEvent: onEventMock,
    })

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.CONTENT_FILTERED,
      filteredCategories: [
        {category: 'self_harm', severity: '2'},
        {category: 'violence', severity: '1'},
      ],
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [],
      finishReason: 'content_filter',
    })
  })

  it('should handle normal completion with stop finish_reason', async () => {
    const onEventMock = jest.fn()
    const encoder = new TextEncoder()
    const mockReader = {
      read: jest
        .fn()
        .mockResolvedValueOnce({
          value: encoder.encode(
            `${JSON.stringify({
              choices: [
                {
                  delta: {content: '<<—[file1.txt]\nTest content\n—>>\n'},
                  finish_reason: 'stop',
                },
              ],
            })}\n\n`,
          ),
          done: false,
        })
        .mockResolvedValueOnce({done: true}),
    }

    ;(makeCAPIRequest as jest.Mock).mockImplementation(async () => ({
      ok: true,
      body: {
        getReader: () => mockReader,
      },
    }))

    await generateIteration({
      prompt: 'Test prompt',
      generationType: 'generate',
      editorState: {files: {}},
      refinementHistory: [],
      apiURL: 'https://api.example.com',
      authTokenProvider: {
        getAuthToken: async () => new AuthToken('valid-token', '2023-10-01T00:00:00Z', []),
      } as CopilotAuthTokenProvider,
      onEvent: onEventMock,
    })

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Test content'}],
      finishReason: 'stop',
    })
  })

  it('should handle signal aborted errors gracefully', async () => {
    const onEventMock = jest.fn()
    const error = new Error('The operation was aborted')
    error.name = 'AbortError'

    // Create an aborted signal
    const controller = new AbortController()
    const signal = controller.signal
    controller.abort()

    // Mock the makeCAPIRequest to throw an AbortError
    ;(makeCAPIRequest as jest.Mock).mockRejectedValue(error)

    // The function should throw, but not emit an error event
    await expect(
      generateIteration({
        prompt: 'Test prompt',
        generationType: 'generate',
        editorState: {files: {}},
        refinementHistory: [],
        apiURL: 'https://api.example.com',
        authTokenProvider: {
          getAuthToken: async () => new AuthToken('valid-token', '2023-10-01T00:00:00Z', []),
        } as CopilotAuthTokenProvider,
        onEvent: onEventMock,
        signal,
      }),
    ).rejects.toThrow(error)

    // Since the signal was aborted, we should NOT emit an error event
    expect(onEventMock).not.toHaveBeenCalledWith({
      type: FileStreamEventType.ERROR,
      error: expect.any(Error),
    })
  })
})
