import type {CopilotChatManager} from '../copilot-chat-manager'
import type {CopilotChatService} from '../copilot-chat-service'
import {CopilotTextAttacher} from '../copilot-text-attacher'

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

const createMockManager = (mockCompletionsResponse: string) => {
  const manager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
  manager.service = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
  manager.dispatch = jest.fn()
  manager.service.getSimpleCompletion = jest
    .fn()
    .mockResolvedValue({ok: true, payload: mockCompletionsResponse, status: 200})
  return manager
}

// Construct a file with `text()` implemented (it's not supported in JSDOM)
const createFile = (content: string, name: string, type: string) => {
  const file = new File([content], name, {type})
  Object.defineProperty(file, 'text', {
    value: jest.fn().mockResolvedValue(content),
  })
  return file
}

describe('CopilotTextAttacher', () => {
  describe('isAttachable', () => {
    it('returns true for valid text mime type and size within limit', async () => {
      const file = createFile('content', 'test.txt', 'text/plain')
      expect(await CopilotTextAttacher.isAttachable(file)).toBe(true)
    })

    it('returns false for binary content', async () => {
      const file = createFile('\u0000\u0001\u0002\u00FF\u00FE', 'test.txt', 'image/png')
      expect(await CopilotTextAttacher.isAttachable(file)).toBe(false)
    })

    it('returns false for file size exceeding limit', async () => {
      const largeContent = new Array(CopilotTextAttacher.getAttachmentSizeLimit() + 100).join('a')
      const file = createFile(largeContent, 'test.txt', 'text/plain')
      expect(await CopilotTextAttacher.isAttachable(file)).toBe(false)
    })
  })

  describe('generateFileName', () => {
    it('generates a valid file name from the manager response', async () => {
      const manager = createMockManager('valid-name.txt')
      const textAttacher = new CopilotTextAttacher(manager, new Set())

      const name = await textAttacher['generateFileName']('file content', 'text/plain')
      expect(name).toBe('valid-name.txt')
    })

    it('falls back to default file name if manager response is invalid', async () => {
      const manager = createMockManager('invalid name')
      const textAttacher = new CopilotTextAttacher(manager, new Set())

      const name = await textAttacher['generateFileName']('file content', 'text/plain')
      expect(name).toBe('untitled.txt')
    })

    it('handles backtick-wrapped names correctly', async () => {
      const manager = createMockManager('`backtick-name.txt`')
      const textAttacher = new CopilotTextAttacher(manager, new Set())

      const name = await textAttacher['generateFileName']('file content', 'text/plain')
      expect(name).toBe('backtick-name.txt')
    })
  })

  describe('addAttachment', () => {
    it('adds and replaces references for valid files', async () => {
      const manager = createMockManager('valid-name.txt')
      const addReferenceMock = jest.fn()
      const replaceReferenceMock = jest.fn()
      manager.addReference = addReferenceMock
      manager.replaceReference = replaceReferenceMock
      const textAttacher = new CopilotTextAttacher(manager, new Set())
      const file = createFile('content', 'test.txt', 'text/plain')

      await textAttacher.addAttachment(file)

      expect(addReferenceMock).toHaveBeenCalledTimes(1)
      expect(replaceReferenceMock).toHaveBeenCalledTimes(1)
    })

    it('does not add references for invalid files', async () => {
      const manager = createMockManager('invalid name')
      const addReferenceMock = jest.fn()
      const replaceReferenceMock = jest.fn()
      const addAmbientErrorMock = jest.fn()
      manager.addReference = addReferenceMock
      manager.replaceReference = replaceReferenceMock
      manager.addAmbientError = addAmbientErrorMock
      const textAttacher = new CopilotTextAttacher(manager, new Set())
      const file = createFile('\u0000\u0001\u0002\u00FF\u00FE', 'test.txt', 'image/png')

      await textAttacher.addAttachment(file)

      expect(addReferenceMock).not.toHaveBeenCalled()
      expect(replaceReferenceMock).not.toHaveBeenCalled()
      expect(addAmbientErrorMock).toHaveBeenCalledWith(
        '"test.txt" has an unsupported file type. Please try again with a plain text file',
      )
    })

    it('handles errors during file processing and dispatches correctly', async () => {
      const manager = createMockManager('valid-name.txt')
      const addReferenceMock = jest.fn()
      const removeReferenceMock = jest.fn()
      const addAmbientErrorMock = jest.fn()
      const dispatchMock = jest.fn()

      manager.addReference = addReferenceMock
      manager.removeReference = removeReferenceMock
      manager.addAmbientError = addAmbientErrorMock
      manager.dispatch = dispatchMock

      const textAttacher = new CopilotTextAttacher(manager, new Set())
      const file = createFile('content', 'test.txt', 'text/plain')

      // Mock makeReference to throw an error
      const makeReferenceSpy = jest
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .spyOn(textAttacher as any, 'makeReference')
        .mockRejectedValue(new Error('Processing failed'))

      await textAttacher.addAttachment(file)

      expect(addReferenceMock).toHaveBeenCalledTimes(1)
      const placeholder = addReferenceMock.mock.calls[0][0]

      expect(dispatchMock).toHaveBeenCalledWith({type: 'WAITING_ON_ATTACHMENT', loading: true})
      expect(dispatchMock).toHaveBeenCalledWith({type: 'WAITING_ON_ATTACHMENT', loading: false})

      // Check error handling
      expect(addAmbientErrorMock).toHaveBeenCalledWith('Failed to process file. Please try again.')
      expect(removeReferenceMock).toHaveBeenCalledWith(placeholder)
      expect(makeReferenceSpy).toHaveBeenCalledWith(file, undefined)
    })
  })

  describe('uniqueFileName', () => {
    it('returns the same name if it is already unique', () => {
      const manager = createMockManager('')
      const textAttacher = new CopilotTextAttacher(manager, new Set(['existing-file.txt']))
      const name = textAttacher['uniqueFileName']('new-file.txt')
      expect(name).toBe('new-file.txt')
    })

    it('appends a number to the name if it is not unique', () => {
      const manager = createMockManager('')
      const textAttacher = new CopilotTextAttacher(manager, new Set(['new-file.txt']))
      const name = textAttacher['uniqueFileName']('new-file.txt')
      expect(name).toBe('new-file2.txt')
    })

    it('increments the appended number until a unique name is found', () => {
      const manager = createMockManager('')
      const textAttacher = new CopilotTextAttacher(manager, new Set(['new-file.txt', 'new-file2.txt']))
      const name = textAttacher['uniqueFileName']('new-file.txt')
      expect(name).toBe('new-file3.txt')
    })

    it('handles names without extensions correctly', () => {
      const manager = createMockManager('')
      const textAttacher = new CopilotTextAttacher(manager, new Set(['newfile']))
      const name = textAttacher['uniqueFileName']('newfile')
      expect(name).toBe('newfile2')
    })

    it('handles names without extensions correctly when multiple conflicts exist', () => {
      const manager = createMockManager('')
      const textAttacher = new CopilotTextAttacher(manager, new Set(['newfile', 'newfile2']))
      const name = textAttacher['uniqueFileName']('newfile')
      expect(name).toBe('newfile3')
    })
  })
})
