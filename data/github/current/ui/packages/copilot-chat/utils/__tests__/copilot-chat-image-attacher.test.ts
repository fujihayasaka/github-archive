import {sendEvent} from '@github-ui/hydro-analytics'

import {getImageReferenceMock, getModelMock, getReducerStateMock} from '../../test-utils/mock-data'
import {CopilotAutocompleteManager} from '../copilot-autocompletions'
import type {CopilotChatManager} from '../copilot-chat-manager'
import type {CopilotChatState} from '../copilot-chat-reducer'
import {CopilotImageAttacher} from '../copilot-image-attacher'

jest.mock('@github-ui/feature-flags')
jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

describe('static functions', () => {
  test('getAllowedImageFileExtensions', () => {
    const model = getModelMock()
    let allowedImageFileExtensions = CopilotImageAttacher.getAllowedImageFileExtensions(model)
    expect(allowedImageFileExtensions).toBe('.jpeg,.png,.webp,.gif,.jpg')

    model.capabilities.family = 'gemini-2.0-flash'

    model.capabilities.limits.vision = {
      // eslint-disable-next-line camelcase
      supported_media_types: ['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif'],
    }
    allowedImageFileExtensions = CopilotImageAttacher.getAllowedImageFileExtensions(model)
    expect(allowedImageFileExtensions).toBe('.png,.jpeg,.webp,.jpg')
  })

  test('isTypeAllowed', () => {
    const model = getModelMock()
    let imageMimeTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/webp']
    for (const type of imageMimeTypes) {
      expect(CopilotImageAttacher.isTypeAllowed(type, model)).toBe(true)
    }

    let disallowedMimeTypes = ['image/tiff', 'image/bmp', 'image/svg+xml']
    for (const type of disallowedMimeTypes) {
      expect(CopilotImageAttacher.isTypeAllowed(type, model)).toBe(false)
    }

    model.capabilities.family = 'gemini-2.0-flash'
    model.capabilities.limits.vision = {
      // eslint-disable-next-line camelcase
      supported_media_types: ['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif'],
    }
    imageMimeTypes = ['image/png', 'image/jpeg', 'image/webp']
    for (const type of imageMimeTypes) {
      expect(CopilotImageAttacher.isTypeAllowed(type, model)).toBe(true)
    }

    disallowedMimeTypes = ['image/gif', 'image/tiff', 'image/bmp', 'image/svg+xml']
    for (const type of disallowedMimeTypes) {
      expect(CopilotImageAttacher.isTypeAllowed(type, model)).toBe(false)
    }
  })

  describe('#makeImageReference', () => {
    const mockUUID = 'mocked-uuid-with-enough-segments'

    beforeAll(() => {
      jest.spyOn(globalThis.crypto, 'randomUUID').mockReturnValue(mockUUID)
    })

    afterAll(() => {
      jest.clearAllMocks()
    })

    test('returns an ImageReference', () => {
      const name = 'name.png'
      const blob = new Blob(['Some test content'], {type: 'image/png'})
      const file: File = new File([blob], name, {
        type: 'image/png',
        lastModified: Date.now(),
      })
      const abortSignal = new AbortController().signal

      const result = CopilotImageAttacher.makeImageReference(file, abortSignal)

      expect(result).toEqual({
        id: mockUUID,
        attachment: {
          key: mockUUID,
          file,
          isLoaded: false,
          hasError: false,
        },
        type: 'image',
        name,
      })
    })

    test('returns a default name when not provided', () => {
      const blob = new Blob(['Some test content'], {type: 'image/png'})
      const file: File = new File([blob], '', {
        type: 'image/png',
        lastModified: Date.now(),
      })
      const abortSignal = new AbortController().signal

      const result = CopilotImageAttacher.makeImageReference(file, abortSignal)
      expect(result).toEqual({
        id: mockUUID,
        attachment: {
          key: mockUUID,
          file,
          isLoaded: false,
          hasError: false,
        },
        type: 'image',
        name: 'Image',
      })
    })
  })
})

describe('addImageAttachment', () => {
  let attacher: CopilotImageAttacher
  let autocomplete: CopilotAutocompleteManager
  let state: CopilotChatState
  let manager: CopilotChatManager
  let abortSignal: AbortSignal
  const mockAddReference = jest.fn()
  const mockSetImageAttachmentUploaded = jest.fn()
  const mockAddAmbientError = jest.fn()

  const mockUUID = 'mocked-uuid-with-enough-segments'

  beforeAll(() => {
    jest.spyOn(globalThis.crypto, 'randomUUID').mockReturnValue(mockUUID)
  })

  beforeEach(() => {
    manager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
    state = getReducerStateMock()
    manager.addAmbientError = mockAddAmbientError
    manager.dispatch = jest.fn()
    autocomplete = new CopilotAutocompleteManager(manager)
    attacher = new CopilotImageAttacher(state, manager, autocomplete)

    abortSignal = new AbortController().signal

    manager.addReference = mockAddReference
    manager.setImageAttachmentUploaded = mockSetImageAttachmentUploaded
  })

  test('attaches image as base64', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    await attacher.addImageAttachment(file, abortSignal)

    const expectedReference = expect.objectContaining({
      id: mockUUID,
      name: file.name,
      type: 'image',
      attachment: expect.objectContaining({
        key: mockUUID,
        file,
      }),
    })

    expect(mockAddReference).toHaveBeenCalledWith(expectedReference, 'autocomplete')
  })

  test('error: only one image per reference', async () => {
    const startingRef = getImageReferenceMock()
    state.currentReferences = [startingRef]

    const blob2 = new Blob(['Some test content'], {type: 'image/png'})
    const file2: File = new File([blob2], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    await attacher.addImageAttachment(file2, abortSignal)

    expect(mockAddAmbientError).toHaveBeenCalledWith('Only one image can be uploaded at a time')
  })

  test('emits image_added events for tracking upload modalities', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    await attacher.addImageAttachment(file, abortSignal, 'paste')
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'paste'})
  })

  test('sets image_added event uploadType to unknown if one is not given', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })
    await attacher.addImageAttachment(file, abortSignal)
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'unknown'})
  })
})
