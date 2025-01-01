/* eslint eslint-comments/no-use: off */
/* eslint-disable testing-library/render-result-naming-convention */

import {act, render} from '@testing-library/react'
import type {ModelState} from '../../../../../types'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockModelState} from '../../../__tests__/mocks'
import {AttachmentsProvider, useChatAttachments} from '../AttachmentsProvider'
import {mockPlaygroundState} from '../../__tests__/mocks'
import {fireFileDropEvent, testFile} from '../../__tests__/test-utils'
import {AttachmentDropzone} from '../AttachmentDropzone'
import {FileReference} from '../file-reference'

function testRender(modelStates?: ModelState[]) {
  let current: ReturnType<typeof useChatAttachments>

  const TestEl = () => {
    current = useChatAttachments()
    return <AttachmentDropzone enabled />
  }

  const state = modelStates ? mockPlaygroundState({models: modelStates}) : mockPlaygroundState()

  const {rerender, container} = render(<TestEl />, {
    wrapper: ({children}) => (
      <PlaygroundStateProvider state={state}>
        <AttachmentsProvider>{children}</AttachmentsProvider>
      </PlaygroundStateProvider>
    ),
  })

  return {
    rerender,
    get element() {
      // eslint-disable-next-line testing-library/no-container
      return container.getElementsByTagName('file-attachment')[0]! as HTMLElement
    },
    get state() {
      return current[0]
    },
    get api() {
      return current[1]
    },
  }
}

describe('useChatAttachments', () => {
  test('initially has no attachments', () => {
    const hook = testRender()
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('allows a file to be uploaded', () => {
    const hook = testRender()
    fireFileDropEvent([testFile()], hook.element)
    expect(hook.state.attachments).toHaveLength(1)
  })

  test('allows files to be reset', () => {
    const hook = testRender()
    fireFileDropEvent([testFile()], hook.element)
    expect(hook.state.attachments).toHaveLength(1)
    act(() => hook.api.reset())
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('allows files to be removed', () => {
    const hook = testRender()
    fireFileDropEvent([testFile()], hook.element)
    expect(hook.state.attachments).toHaveLength(1)
    act(() => hook.api.removeFile(hook.state.attachments[0]!))
    expect(hook.state.attachments).toHaveLength(0)
  })

  test('allows files to be programmatically added', () => {
    const hook = testRender()
    expect(hook.state.attachments).toHaveLength(0)
    act(() => hook.api.addFiles([new FileReference(testFile())]))
    expect(hook.state.attachments).toHaveLength(1)
  })

  describe('validation', () => {
    test("doesn't allow more than three file", () => {
      const hook = testRender()
      fireFileDropEvent([testFile(), testFile(), testFile(), testFile()], hook.element)
      expect(hook.state.errorMessage).toBe('Sorry, we only support 3 files right now.')
      expect(hook.state.attachments).toHaveLength(0)
    })

    test("doesn't allow more than the maximum number of imagesPerTurn when on comparison mode", () => {
      const model1 = {
        ...mockModelState,
        modelInputSchema: {...mockModelState.modelInputSchema, capabilities: {chat: {imagesPerTurn: 2}}},
      }
      const model2 = {...mockModelState}
      const modelStates = [model1, model2]
      const hook = testRender(modelStates)
      fireFileDropEvent([testFile(), testFile(), testFile()], hook.element)
      expect(hook.state.errorMessage).toBe('Sorry, at least one of the models only supports up to 2 files per message.')
      expect(hook.state.attachments).toHaveLength(0)
    })

    test("doesn't allow unsupported files", () => {
      const hook = testRender()
      const file = testFile('file.pdf', 'application/pdf')
      fireFileDropEvent([file], hook.element)
      expect(hook.state.errorMessage).toBe("Sorry, it look's like that file was not supported.")
      expect(hook.state.attachments).toHaveLength(0)
    })

    test("doesn't allow files that are too large", () => {
      const hook = testRender()
      const file = testFile('file.jpg', 'image/jpg', 1024 * 1024 + 1)
      fireFileDropEvent([file], hook.element)
      expect(hook.state.errorMessage).toBe('Sorry, we only support files up to 1MB.')
      expect(hook.state.attachments).toHaveLength(0)
    })
  })
})
