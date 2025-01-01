import {noop} from '@github-ui/noop'

import {UploadableFileAttachment} from '../uploadable-file-attachment'

jest.mock('@github-ui/attachments/util/resource', () => ({
  resource: jest.fn().mockImplementation((fn: () => Promise<unknown>) => ({load: () => fn()})),
}))

jest.mock('@github-ui/attachments/uploadable', () => ({
  createPolicy: jest.fn().mockResolvedValue({url: 'mock-policy-url'}),
  uploadFile: jest.fn().mockResolvedValue(undefined),
  complete: jest.fn().mockResolvedValue({id: 'mock-asset-id', href: 'mock-asset-href'}),
}))

function mockImage({succeedLoading}: {succeedLoading: boolean} = {succeedLoading: true}) {
  global.Image = class {
    onload = succeedLoading ? noop : null
    onerror = succeedLoading ? null : noop
    width = 123
    height = 456
    set src(_val: string) {
      if (succeedLoading && typeof this.onload === 'function') this.onload()
      else if (!succeedLoading && typeof this.onerror === 'function') this.onerror()
    }
  } as typeof global.Image
}

describe('UploadableFileAttachment', () => {
  let originalImage: typeof global.Image

  beforeEach(() => {
    jest.clearAllMocks()

    originalImage = global.Image
    mockImage()
  })

  afterEach(() => {
    global.Image = originalImage
  })

  describe('dimensions for files after prefetch', () => {
    it('should set width and height for image files after prefetch', async () => {
      const imageFile = new File(['fake'], 'test.png', {type: 'image/png'})
      const attachment = new UploadableFileAttachment('test-key', imageFile)

      await attachment.prefetch()
      expect(attachment.width).toBe(123)
      expect(attachment.height).toBe(456)
    })

    it('should set width and height to undefined for non-image files after prefetch', async () => {
      const textFile = new File(['Hello world'], 'test.txt', {type: 'text/plain'})
      const attachment = new UploadableFileAttachment('test-key', textFile)

      await attachment.prefetch()
      expect(attachment.width).toBeUndefined()
      expect(attachment.height).toBeUndefined()
    })

    it('should reject the promise if image loading fails (image.onerror)', async () => {
      mockImage({succeedLoading: false})

      const imageFile = new File(['fake'], 'test.png', {type: 'image/png'})
      const attachment = new UploadableFileAttachment('test-key', imageFile)

      let error: Error | undefined
      try {
        await attachment.prefetch()
      } catch (e) {
        error = e as Error
      }

      expect(error).toEqual(new Error('Failed to load image for dimension extraction'))
    })
  })
})
