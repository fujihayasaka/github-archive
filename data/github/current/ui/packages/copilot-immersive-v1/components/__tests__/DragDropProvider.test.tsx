import type {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotImageAttacher as CopilotImageAttacherType} from '@github-ui/copilot-chat/utils/copilot-image-attacher'
import {render, type RenderResult} from '@testing-library/react'
import {screen} from '@testing-library/react'
import {act} from 'react'

import {DragDropProvider, useDragDropContext} from '../DragDropContext'

jest.mock('@github-ui/copilot-chat/utils/copilot-image-attacher', () => {
  const CopilotImageAttacherMock = jest.fn().mockImplementation(() => ({
    addImageAttachments: jest.fn(),
  }))

  return {
    CopilotImageAttacher: Object.assign(CopilotImageAttacherMock, {
      isTypeAllowed: jest.fn(() => true),
      getAllowedFiles: jest.fn(() => [[new File(['test'], 'test.png', {type: 'image/png'})], []]),
    }),
  }
})

const DummyComponent = () => {
  const {isDragging} = useDragDropContext()
  return <div data-testid="drag-status">{isDragging ? 'Dragging' : 'Not dragging'}</div>
}

const PassiveComponent = () => {
  return <div data-testid="drag-status">DragDrop Disabled</div>
}

const model: CopilotChatModel = {
  capabilities: {supports: {vision: true}},
} as CopilotChatModel

const state = {} as CopilotChatState
const manager = {} as CopilotChatManager

const setup = (dragDropEnabled = true): RenderResult => {
  return render(
    dragDropEnabled ? (
      <DragDropProvider model={model} state={state} manager={manager}>
        <DummyComponent />
      </DragDropProvider>
    ) : (
      <PassiveComponent />
    ),
  )
}

describe('DragDropProvider', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('sets isDragging to true and false on drag events', () => {
    // Ensure setup has completed before querying screen
    act(() => {
      setup()
    })

    act(() => {
      window.dispatchEvent(new Event('dragenter'))
    })
    expect(screen.getByTestId('drag-status').textContent).toBe('Dragging')

    act(() => {
      window.dispatchEvent(new Event('dragleave'))
    })
    expect(screen.getByTestId('drag-status').textContent).toBe('Not dragging')
  })

  it('handles file drop and calls CopilotImageAttacher', () => {
    setup(true)

    const blob = new Blob(['Some test content'], {type: 'image/png'})
    const fakeFile = new File([blob], 'test.png', {type: 'image/png'})

    const dataTransfer = {
      files: [fakeFile],
      types: [],
      items: [],
      dropEffect: 'none',
      effectAllowed: 'all',
      getData: () => '',
      setData: () => {},
      clearData: () => {},
    } as unknown as DataTransfer

    const dropEvent = new Event('drop') as DragEvent
    Object.defineProperty(dropEvent, 'dataTransfer', {value: dataTransfer})

    act(() => {
      window.dispatchEvent(dropEvent)
    })

    const CopilotImageAttacherConstructor = CopilotImageAttacherType as unknown as jest.Mock
    const constructorCalls = CopilotImageAttacherConstructor.mock.results

    expect(constructorCalls.length).toBeGreaterThan(0)

    const instance = constructorCalls[0]!.value
    expect(instance.addImageAttachments).toHaveBeenCalledWith(
      [expect.objectContaining({name: 'test.png', type: 'image/png'})],
      'drag',
    )
  })

  it('does not set isDragging if drag and drop is disabled', () => {
    act(() => {
      setup(false) // no DragDropProvider
    })

    act(() => {
      window.dispatchEvent(new Event('dragenter'))
    })
    expect(screen.getByTestId('drag-status').textContent).toBe('DragDrop Disabled')
  })
})
