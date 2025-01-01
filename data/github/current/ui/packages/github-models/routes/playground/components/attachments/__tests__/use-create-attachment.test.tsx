// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type React from 'react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderHook} from '@testing-library/react'
import {useCreateAttachment} from '../use-create-attachment'
import {Base64FileAttachment} from '../base64-file-attachment'
import {UploadableFileAttachment} from '../uploadable-file-attachment'
import {MockFileAttachment, testFile} from '@github-ui/attachments/test-utils'

jest.mock('../base64-file-attachment', () => ({
  Base64FileAttachment: jest.fn((file: File) => new MockFileAttachment(file)),
}))
jest.mock('../uploadable-file-attachment', () => ({
  UploadableFileAttachment: jest.fn((file: File) => new MockFileAttachment(file)),
}))
const mockBase64FileAttachment = jest.mocked(Base64FileAttachment)
const mockUploadableFileAttachment = jest.mocked(UploadableFileAttachment)

beforeEach(() => {
  jest.clearAllMocks()
})

describe('useCreateAttachment', () => {
  test('returns a factory', () => {
    const {result} = hook()
    expect(result.current).toBeInstanceOf(Function)
  })

  test('uses the base64 upload without uploadable feature flag', () => {
    const {result} = hook()

    result.current(testFile())

    expect(mockBase64FileAttachment).toHaveBeenCalledTimes(1)
    expect(mockUploadableFileAttachment).toHaveBeenCalledTimes(0)
  })

  test('when under the feature flag, use uploadable attachment', () => {
    const {result} = hook({
      appPayload: {
        enabled_features: {
          github_models_uploadable_attachments: true,
        },
      },
    })

    result.current(testFile())

    expect(mockBase64FileAttachment).toHaveBeenCalledTimes(0)
    expect(mockUploadableFileAttachment).toHaveBeenCalledTimes(1)
  })

  describe('when UploadableFileAttachment', () => {
    function testHook() {
      return hook({
        appPayload: {
          enabled_features: {
            github_models_uploadable_attachments: true,
          },
        },
      })
    }

    test('passes an abort signal', () => {
      const {result} = testHook()

      const file = testFile()
      result.current(file)

      expect(mockUploadableFileAttachment).toHaveBeenCalledWith(file, expect.any(AbortSignal))
    })

    test('reuses the same signal between calls', () => {
      const {result} = testHook()
      result.current(testFile())
      result.current(testFile())

      expect(mockUploadableFileAttachment).toHaveBeenCalledTimes(2)

      const firstSignal = mockUploadableFileAttachment.mock.calls.at(0)?.[1]
      const secondSignal = mockUploadableFileAttachment.mock.calls.at(1)?.[1]

      expect(firstSignal).toBeInstanceOf(AbortSignal)
      expect(secondSignal).toBeInstanceOf(AbortSignal)

      expect(firstSignal).toBe(secondSignal)
    })

    test('aborts the signal on unmount', () => {
      const {result, unmount} = testHook()
      result.current(testFile())

      expect(mockUploadableFileAttachment).toHaveBeenCalledTimes(1)
      const signal = mockUploadableFileAttachment.mock.calls.at(0)?.[1]
      expect(signal).toBeInstanceOf(AbortSignal)

      expect(signal!.aborted).toBe(false)

      unmount()

      expect(signal!.aborted).toBe(true)
    })
  })
})

function hook(wrapperProps: React.ComponentProps<typeof Wrapper> = {}) {
  return renderHook(() => useCreateAttachment(), {
    wrapper(props) {
      return <Wrapper {...wrapperProps} {...props} />
    },
  })
}
