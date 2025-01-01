/* eslint eslint-comments/no-use: off */
/* eslint-disable testing-library/render-result-naming-convention */

import {act, renderHook} from '@testing-library/react'
import type React from 'react'

import {AttachmentsProvider, useAttachments} from '../AttachmentsProvider'
import {mockFileAttachment, testFile} from '../test-utils'
import type {FileAttachment} from '../types'

describe('useAttachments', () => {
  test('initially has no attachments', () => {
    const hook = happyTestRender()
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('allows a file to be uploaded', () => {
    const hook = happyTestRender()
    addFiles(hook)
    expect(hook.state.attachments).toHaveLength(1)
  })

  test('allows files to be reset', () => {
    const hook = happyTestRender()
    addFiles(hook)
    expect(hook.state.attachments).toHaveLength(1)
    act(() => hook.api.reset())
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('allows files to be removed', () => {
    const hook = happyTestRender()
    addFiles(hook)
    expect(hook.state.attachments).toHaveLength(1)
    act(() => hook.api.remove(hook.state.attachments[0]!))
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('respects the attachLimit', () => {
    const hook = testRender({
      attachLimit: 2,
    })
    addFiles(hook, [mockFileAttachment(), mockFileAttachment(), mockFileAttachment()])
    expect(hook.state.errorMessage).toBe('Sorry, only up to 2 files per message are supported.')
    expect(hook.state.attachments).toHaveLength(0)
  })

  test("doesn't allow unsupported files", () => {
    const hook = happyTestRender()
    const file = testFile('file.pdf', 'application/pdf')
    addFiles(hook, [mockFileAttachment(file)])
    expect(hook.state.errorMessage).toBe("Sorry, it look's like that file was not supported.")
    expect(hook.state.attachments).toHaveLength(0)
  })

  test("doesn't allow files that are too large", () => {
    const hook = testRender({
      attachLimit: 3,
      fileSizeLimit: 1024,
    })
    const file = testFile('file.jpg', 'image/jpg', 1025)
    addFiles(hook, [mockFileAttachment(file)])
    expect(hook.state.errorMessage).toBe('Sorry, we only support files up to 1KB.')
    expect(hook.state.attachments).toHaveLength(0)
  })
})

// ---

function addFiles(hook: ReturnType<typeof testRender>, files?: FileAttachment[]) {
  files ||= [mockFileAttachment()]
  act(() => hook.api.addFiles(files))
}

function happyTestRender() {
  return testRender({attachLimit: 3})
}

function testRender(wrapperProps: React.ComponentProps<typeof AttachmentsProvider>) {
  const hook = renderHook(() => useAttachments(), {
    wrapper(props) {
      return <AttachmentsProvider {...wrapperProps} {...props} />
    },
  })

  return {
    rerender: hook.rerender.bind(hook),
    unmount: hook.unmount.bind(hook),
    get state() {
      return hook.result.current[0]
    },
    get api() {
      return hook.result.current[1]
    },
  }
}
