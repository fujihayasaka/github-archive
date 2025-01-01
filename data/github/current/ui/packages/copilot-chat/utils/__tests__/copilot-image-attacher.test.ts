import {sendEvent} from '@github-ui/hydro-analytics'

import {getImageReferenceMock, getModelMock, getReducerStateMock} from '../../test-utils/mock-data'
import type {CopilotChatManager} from '../copilot-chat-manager'
import type {CopilotChatState} from '../copilot-chat-reducer'
import {copilotFeatureFlags} from '../copilot-feature-flags'
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

  describe('getAllowedFiles', () => {
    const model = getModelMock()

    test('returns all allowed images and no other files', () => {
      const png = new File([new Blob(['a'], {type: 'image/png'})], 'a.png', {type: 'image/png'})
      const jpeg = new File([new Blob(['b'], {type: 'image/jpeg'})], 'b.jpeg', {type: 'image/jpeg'})
      const files = [png, jpeg]
      const [allowed, other] = CopilotImageAttacher.getAllowedFiles(files, model)
      expect(allowed).toEqual([png, jpeg])
      expect(other).toEqual([])
    })

    test('returns only allowed images, separates others', () => {
      const png = new File([new Blob(['a'], {type: 'image/png'})], 'a.png', {type: 'image/png'})
      const pdf = new File([new Blob(['b'], {type: 'application/pdf'})], 'b.pdf', {type: 'application/pdf'})
      const files = [png, pdf]
      const [allowed, other] = CopilotImageAttacher.getAllowedFiles(files, model)
      expect(allowed).toEqual([png])
      expect(other).toEqual([pdf])
    })

    test('returns empty allowed array if no images', () => {
      const pdf = new File([new Blob(['b'], {type: 'application/pdf'})], 'b.pdf', {type: 'application/pdf'})
      const txt = new File([new Blob(['c'], {type: 'text/plain'})], 'c.txt', {type: 'text/plain'})
      const files = [pdf, txt]
      const [allowed, other] = CopilotImageAttacher.getAllowedFiles(files, model)
      expect(allowed).toEqual([])
      expect(other).toEqual([pdf, txt])
    })

    test('returns empty arrays if input is empty', () => {
      const files: File[] = []
      const [allowed, other] = CopilotImageAttacher.getAllowedFiles(files, model)
      expect(allowed).toEqual([])
      expect(other).toEqual([])
    })
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

      const result = CopilotImageAttacher.makeImageReference(file, 'some-thread-id')

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

      const result = CopilotImageAttacher.makeImageReference(file, 'some-thread-id')
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

describe('addImageAttachments', () => {
  let attacher: CopilotImageAttacher
  let state: CopilotChatState
  let manager: CopilotChatManager
  const mockAddReference = jest.fn()
  const mockRemoveReference = jest.fn()
  const mockReplaceReference = jest.fn()
  const mockSetImageAttachmentUploaded = jest.fn()
  const mockAddAmbientError = jest.fn()
  const mockCreateThread = jest.fn()
  const mockGetPendingThreadId = jest.fn(() => null)
  const mockSetPendingThreadId = jest.fn()

  const mockUUID = 'mocked-uuid-with-enough-segments'

  beforeAll(() => {
    jest.spyOn(globalThis.crypto, 'randomUUID').mockReturnValue(mockUUID)
  })

  beforeEach(() => {
    manager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
    state = getReducerStateMock()
    manager.addAmbientError = mockAddAmbientError
    manager.dispatch = jest.fn()
    attacher = new CopilotImageAttacher(state, manager)

    manager.addReference = mockAddReference
    manager.setImageAttachmentUploaded = mockSetImageAttachmentUploaded
    manager.createThread = mockCreateThread
    manager.setPendingThreadId = mockSetPendingThreadId
    manager.getPendingThreadId = mockGetPendingThreadId
    manager.removeReference = mockRemoveReference
    manager.replaceReference = mockReplaceReference
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('attaches image as base64', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    await attacher.addImageAttachments([file])

    const expectedReference = expect.objectContaining({
      type: 'loading',
      title: file.name,
      id: mockUUID, // or expect.any(String) if the UUID is generated dynamically
      isClientOnly: true,
    })

    expect(mockAddReference).toHaveBeenCalledWith(expectedReference, 'image-attacher')
  })

  test('attaches multiple images when flag is enabled', async () => {
    const startingRef = getImageReferenceMock()
    state.currentReferences = [startingRef]

    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example1.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    const imageReferenceSpy = jest.spyOn(CopilotImageAttacher, 'makeImageReference')
    imageReferenceSpy.mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'attachMultipleImages', 'get').mockReturnValue(true)
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)

    await attacher.addImageAttachments([file])
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'unknown'})

    expect(imageReferenceSpy).toHaveBeenCalledWith(file, 'threadId')
  })

  test('error: only one image reference allowed when flag disabled', async () => {
    const startingRef = getImageReferenceMock()
    state.currentReferences = [startingRef]

    const blob2 = new Blob(['Some test content'], {type: 'image/png'})
    const file2: File = new File([blob2], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    jest.spyOn(copilotFeatureFlags, 'attachMultipleImages', 'get').mockReturnValue(false)

    await attacher.addImageAttachments([file2])

    expect(mockAddAmbientError).toHaveBeenCalledWith('Only one image can be uploaded at a time')
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.error', {type: 'file_limit_reached'})
    expect(mockSetPendingThreadId).not.toHaveBeenCalled()
  })

  test('error: unsupported file upload attempted', async () => {
    const pdfType = 'application/pdf'
    const blob = new Blob(['Some test content'], {type: pdfType})
    const file: File = new File([blob], 'example.txt', {
      type: pdfType,
      lastModified: Date.now(),
    })

    await attacher.addImageAttachments([file])

    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.error', {
      type: 'included_unsupported_file',
      fileTypes: pdfType,
      uploadType: 'unknown',
    })
    expect(mockSetPendingThreadId).not.toHaveBeenCalled()
  })

  test('error: Claude model rejects images with any dimension exceeding 8000 pixels', async () => {
    state.model.id = 'claude-3.5-sonnet-vision'
    state.model.capabilities.supports.vision = true

    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    const imageWidth = 9000
    const imageHeight = 7000

    const mockAttachment = {
      key: mockUUID,
      file,
      isLoaded: false,
      hasError: false,
      width: imageWidth,
      height: imageHeight,
      prefetch: jest.fn().mockResolvedValue(undefined),
      url: jest.fn().mockResolvedValue('mock-url'),
      previewUrl: 'mock-preview-url',
      getDimensions: jest.fn().mockResolvedValue({width: imageWidth, height: imageHeight}),
    }

    const mockImageReference = {
      id: mockUUID,
      attachment: mockAttachment,
      type: 'image' as const,
      name: file.name,
    }

    jest.spyOn(CopilotImageAttacher, 'makeImageReference').mockReturnValue(mockImageReference)

    await attacher.addImageAttachments([file])

    expect(mockAddAmbientError).toHaveBeenCalledWith(
      'The image you uploaded exceeds the maximum allowed dimensions for Claude models. Please try again with another model.',
    )
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.error', {
      type: 'dimension_limit_exceeded',
      width: imageWidth,
      height: imageHeight,
    })
    expect(mockSetPendingThreadId).not.toHaveBeenCalled()
  })

  test('emits image_added events for tracking upload modalities', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    await attacher.addImageAttachments([file], 'paste')
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'paste'})
  })

  test('sets image_added event uploadType to unknown if one is not given', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })
    await attacher.addImageAttachments([file])
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'unknown'})
  })

  test('creates a thread if one is not active and we are attaching images', async () => {
    state.selectedThreadID = null
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    jest.spyOn(CopilotImageAttacher, 'makeImageReference').mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
    mockCreateThread.mockResolvedValueOnce(Promise.resolve({id: 'new-thread-id'}))

    await attacher.addImageAttachments([file])
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'unknown'})
    expect(mockCreateThread).toHaveBeenCalled()
    expect(mockCreateThread).toHaveBeenCalledWith(undefined, false)
  })

  test('passes thread id to getimagereference', async () => {
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    const imageReferenceSpy = jest.spyOn(CopilotImageAttacher, 'makeImageReference')
    imageReferenceSpy.mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)

    await attacher.addImageAttachments([file])
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.vision.image_added', {uploadType: 'unknown'})

    expect(imageReferenceSpy).toHaveBeenCalledWith(file, 'threadId')
  })

  test('passes preventThreadSelection argument to createThread when true', async () => {
    state.selectedThreadID = null
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    jest.spyOn(CopilotImageAttacher, 'makeImageReference').mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
    const mockThread = {id: 'new-thread-id'}
    mockCreateThread.mockResolvedValueOnce(Promise.resolve(mockThread))

    await attacher.addImageAttachments([file], 'unknown', null, true)
    expect(mockCreateThread).toHaveBeenCalledWith(null, true)
  })

  test('stores pending thread ID when creating a new thread with custom copilot id and preventThreadSelection', async () => {
    state.selectedThreadID = null
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })
    const customCopilotId = {id: 1234, owner: 'test-owner'}

    jest.spyOn(CopilotImageAttacher, 'makeImageReference').mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
    const mockThread = {id: 'new-thread-id'}
    mockCreateThread.mockResolvedValueOnce(Promise.resolve(mockThread))

    await attacher.addImageAttachments([file], 'unknown', customCopilotId, true)
    expect(mockSetPendingThreadId).toHaveBeenCalledWith('new-thread-id', customCopilotId)
  })

  test('passes customCopilotId to createThread when provided', async () => {
    state.selectedThreadID = null
    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const file: File = new File([blob], 'example.txt', {
      type: 'image/png',
      lastModified: Date.now(),
    })

    jest.spyOn(CopilotImageAttacher, 'makeImageReference').mockReturnValue(getImageReferenceMock())
    jest.spyOn(copilotFeatureFlags, 'dotcomChatFileUpload', 'get').mockReturnValue(true)
    const mockThread = {id: 'new-thread-id'}
    mockCreateThread.mockResolvedValueOnce(Promise.resolve(mockThread))
    const customCopilotId = {id: 1234, owner: 'test-owner'}

    await attacher.addImageAttachments([file], 'unknown', customCopilotId, false)
    expect(mockCreateThread).toHaveBeenCalledWith(customCopilotId, false)
  })
})
