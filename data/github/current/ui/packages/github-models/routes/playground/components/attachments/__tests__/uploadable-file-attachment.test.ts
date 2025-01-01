import {complete, createPolicy, uploadFile} from '@github-ui/attachments/uploadable'
import {UploadableFileAttachment} from '../uploadable-file-attachment'
import {mockPolicy, testFile} from '@github-ui/attachments/test-utils'

jest.mock('@github-ui/attachments/uploadable', () => ({
  createPolicy: jest.fn().mockName('createPolicy'),
  uploadFile: jest.fn().mockName('uploadFile'),
  complete: jest.fn().mockName('complete'),
}))

const mockCreatePolicy = jest.mocked(createPolicy)
const mockUploadFile = jest.mocked(uploadFile)
const mockComplete = jest.mocked(complete)

beforeEach(() => {
  jest.clearAllMocks()
})

describe('UploadableFileAttachment', () => {
  test('new', () => {
    expect(() => new UploadableFileAttachment(testFile())).not.toThrow()
  })

  test('#key', () => {
    const attachment = new UploadableFileAttachment(testFile())
    expect(attachment.key).toBeDefined()
  })

  test('expose the #file as a member variable', () => {
    const file = testFile()
    const attachment = new UploadableFileAttachment(file)
    expect(attachment.file).toBe(file)
  })

  test('does not upload on creation', () => {
    new UploadableFileAttachment(testFile())

    expect(mockCreatePolicy).toHaveBeenCalledTimes(0)
    expect(mockUploadFile).toHaveBeenCalledTimes(0)
    expect(mockComplete).toHaveBeenCalledTimes(0)
  })

  describe('prefetch', () => {
    test('can prefetch', () => {
      const attachment = new UploadableFileAttachment(testFile())
      expect(attachment.prefetch()).toBeInstanceOf(Promise)
    })
  })

  describe('uploadable assets flow', () => {
    test('happy path', async () => {
      const mockedPolicy = mockPolicy()

      mockCreatePolicy.mockResolvedValueOnce(mockedPolicy)
      mockUploadFile.mockResolvedValueOnce(undefined)
      mockComplete.mockResolvedValueOnce(mockedPolicy.asset)

      const file = testFile()
      const attachment = new UploadableFileAttachment(file)
      await expect(attachment.prefetch()).resolves.toEqual(mockedPolicy.asset)

      expect(mockCreatePolicy).toHaveBeenCalledWith(
        {name: file.name, size: String(file.size), content_type: file.type},
        '/upload/policies/models-attachments',
        expect.any(AbortSignal),
      )
      expect(mockUploadFile).toHaveBeenCalledWith(file, mockedPolicy, expect.any(AbortSignal))
      expect(mockComplete).toHaveBeenCalledWith(mockedPolicy, expect.any(AbortSignal))

      expect(attachment.previewUrl).toBe(mockedPolicy.asset.href)
    })

    test('caches the resource between calls', async () => {
      const mockedPolicy = mockPolicy()

      mockCreatePolicy.mockResolvedValueOnce(mockedPolicy)
      mockUploadFile.mockResolvedValueOnce(undefined)
      mockComplete.mockResolvedValueOnce(mockedPolicy.asset)

      const attachment = new UploadableFileAttachment(testFile())

      const a = await attachment.prefetch()
      const b = await attachment.prefetch()

      expect(a).toBe(b)

      expect(mockCreatePolicy).toHaveBeenCalledTimes(1)
      expect(mockUploadFile).toHaveBeenCalledTimes(1)
      expect(mockComplete).toHaveBeenCalledTimes(1)
    })

    test('throws if there was an error', async () => {
      mockCreatePolicy.mockRejectedValueOnce('some error')
      const attachment = new UploadableFileAttachment(testFile())

      await expect(() => attachment.prefetch()).rejects.toEqual('some error')
    })
  })
})
