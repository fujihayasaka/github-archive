import {act, renderHook} from '@testing-library/react'

import {CommandTask} from '../../utilities/terminal-reducer'
import {ErrorsProvider, useErrors} from '../ErrorsContext'
import {useServerEvents} from '../ServerEventsContext'
import {useTerminalContext} from '../TerminalContext'
import {useWorkbenchPreview} from '../WorkbenchPreviewContext'

// Mock dependencies
jest.mock('../ServerEventsContext', () => ({
  useServerEvents: jest.fn(),
}))

jest.mock('../TerminalContext', () => ({
  useTerminalContext: jest.fn(),
}))

jest.mock('../WorkbenchPreviewContext', () => ({
  useWorkbenchPreview: jest.fn(),
}))

jest.mock('../PublishingContext', () => ({
  usePublishingContext: () => ({publishingStatus: 'unpublished'}),
}))

jest.mock('../IterationHistoryContext', () => ({
  useIterationHistory: jest.fn().mockReturnValue({
    currentRefinementId: 'test-refinement-id',
  }),
}))

jest.mock('../../telemetry/use-analytics', () => ({
  useAnalytics: jest.fn().mockReturnValue(jest.fn()),
}))

jest.mock('../WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn().mockReturnValue({
    isFetching: false,
  }),
}))

describe('ErrorsContext', () => {
  // Setup mocks for dependencies
  beforeEach(() => {
    ;(useServerEvents as jest.Mock).mockReturnValue({
      events: [],
    })
    ;(useTerminalContext as jest.Mock).mockReturnValue({
      state: {
        history: {
          [CommandTask.Deploy]: {
            output: '',
          },
        },
      },
    })
    ;(useWorkbenchPreview as jest.Mock).mockReturnValue({
      runtimeErrors: [], // Updated from errorQueue to runtimeErrors
    })
  })

  describe('ErrorsProvider', () => {
    it('provides editor errors and warnings', () => {
      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      expect(result.current.editorErrors).toEqual([])
      expect(result.current.editorWarnings).toEqual([])

      act(() => {
        result.current.setEditorErrors('src/App.tsx', [
          {
            source: 'editor',
            messageRaw: 'Test error',
            messagePretty: 'Test error',
          },
        ])

        result.current.setEditorWarnings([
          {
            source: 'editor',
            messageRaw: 'Test warning',
          },
        ])
      })

      expect(result.current.editorErrors).toHaveLength(1)
      expect(result.current.editorWarnings).toHaveLength(1)
      expect(result.current.allErrors).toContainEqual(
        expect.objectContaining({
          source: 'editor',
        }),
      )
    })

    it('collects preview errors from server events', () => {
      ;(useServerEvents as jest.Mock).mockReturnValue({
        events: [
          {type: 'build:success'},
          {type: 'build:failed', details: {error: {message: 'First error'}}},
          {type: 'other:event'},
          {type: 'build:failed', details: {error: {message: 'Second error'}}},
        ],
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      expect(result.current.previewBuildErrors).toHaveLength(2)
      expect(result.current.previewBuildErrors[0]?.messageRaw).toBe('First error')
      expect(result.current.previewBuildErrors[1]?.messageRaw).toBe('Second error')
    })

    it('collects runtime errors from preview iframe', () => {
      ;(useWorkbenchPreview as jest.Mock).mockReturnValue({
        runtimeErrors: [
          {
            message: 'Runtime error 1',
            path: '/path/to/file.tsx',
            line: 10,
            column: 5,
          },
        ],
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      expect(result.current.previewRuntimeErrors).toHaveLength(1)
      expect(result.current.previewRuntimeErrors[0]?.messageRaw).toBe('Runtime error 1')
      expect(result.current.previewRuntimeErrors[0]?.source).toBe('preview-runtime')
    })

    it('collects deploy errors from terminal output', () => {
      ;(useTerminalContext as jest.Mock).mockReturnValue({
        state: {
          history: {
            [CommandTask.Deploy]: {
              output: 'Some output\nerror during build:\nError: Deploy failed',
            },
          },
        },
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      expect(result.current.deployBuildErrors).toHaveLength(1)
      expect(result.current.deployBuildErrors[0]?.messageRaw).toBe('error during build:\nError: Deploy failed')
    })

    it('combines all errors in allErrors property', () => {
      // Setup preview errors
      ;(useServerEvents as jest.Mock).mockReturnValue({
        events: [{type: 'build:failed', details: {error: {message: 'Preview error'}}}],
      })

      // Setup deploy errors
      ;(useTerminalContext as jest.Mock).mockReturnValue({
        state: {
          history: {
            [CommandTask.Deploy]: {
              output: 'error during build:\nError: Deploy error',
            },
          },
        },
      })

      // Setup runtime errors
      ;(useWorkbenchPreview as jest.Mock).mockReturnValue({
        runtimeErrors: [
          {
            message: 'Runtime error',
            path: '/path/to/file.tsx',
            line: 10,
            column: 5,
          },
        ],
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      act(() => {
        result.current.setEditorErrors('src/App.tsx', [
          {
            source: 'editor',
            messageRaw: 'Editor error',
          },
        ])
      })

      expect(result.current.allErrors).toHaveLength(4)
      expect(result.current.allErrors).toEqual(
        expect.arrayContaining([
          expect.objectContaining({source: 'editor', messageRaw: 'Editor error'}),
          expect.objectContaining({source: 'preview-build', messageRaw: 'Preview error'}),
          expect.objectContaining({source: 'preview-runtime', messageRaw: 'Runtime error'}),
          expect.objectContaining({source: 'deploy', messageRaw: 'error during build:\nError: Deploy error'}),
        ]),
      )
    })

    it('creates panel errors from preview, deploy, and iframe errors', () => {
      // Setup all error types
      ;(useServerEvents as jest.Mock).mockReturnValue({
        events: [{type: 'build:failed', details: {error: {message: 'Preview error'}}}],
      })
      ;(useTerminalContext as jest.Mock).mockReturnValue({
        state: {
          history: {
            [CommandTask.Deploy]: {
              output: 'error during build:\nError: Deploy error',
            },
          },
        },
      })
      ;(useWorkbenchPreview as jest.Mock).mockReturnValue({
        runtimeErrors: [{message: 'Runtime error', path: '/file.tsx', line: 1, column: 1}],
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      // Editor errors are not included in panelErrors
      act(() => {
        result.current.setEditorErrors('src/App.tsx', [{source: 'editor', messageRaw: 'Editor error'}])
      })

      expect(result.current.panelErrors).toHaveLength(3)
      expect(result.current.panelErrors).not.toContainEqual(expect.objectContaining({source: 'editor'}))
    })

    it('creates iterateErrors with unique errors from preview, deploy, and iframe errors', () => {
      // Setup duplicate errors
      ;(useServerEvents as jest.Mock).mockReturnValue({
        events: [
          {type: 'build:failed', details: {error: {message: 'Duplicate error'}}},
          {type: 'build:failed', details: {error: {message: 'Unique error 1'}}},
        ],
      })
      ;(useTerminalContext as jest.Mock).mockReturnValue({
        state: {
          history: {
            [CommandTask.Deploy]: {
              output: 'error during build:\nError: Duplicate error\nError: Unique error 2',
            },
          },
        },
      })
      ;(useWorkbenchPreview as jest.Mock).mockReturnValue({
        runtimeErrors: [{message: 'Duplicate error', path: '/file.tsx', line: 1, column: 1}],
      })

      const {result} = renderHook(() => useErrors(), {
        wrapper: ({children}) => <ErrorsProvider>{children}</ErrorsProvider>,
      })

      // Should only contain 3 unique errors, not 4
      expect(result.current.iterateErrors.length).toBeLessThanOrEqual(3)

      // Check unique messages (no duplicates)
      const messages = result.current.iterateErrors.map(e => e.messageRaw)
      expect(messages.length).toBe(3)
    })
  })

  describe('useErrors', () => {
    it('throws error when used outside of ErrorsProvider', () => {
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

      expect(() => {
        renderHook(() => useErrors())
      }).toThrow('useErrors must be used within an ErrorsProvider')

      consoleSpy.mockRestore()
    })
  })
})
