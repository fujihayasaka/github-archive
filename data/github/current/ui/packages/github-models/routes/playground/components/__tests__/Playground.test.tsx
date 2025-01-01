import safeStorage from '@github-ui/safe-storage'
import {Playground, type PlaygroundProps} from '../Playground'
import {render} from '@github-ui/react-core/test-utils'
import {act, fireEvent, screen, waitFor, within} from '@testing-library/react'
import {useMemo, useReducer, type PropsWithChildren} from 'react'
import {
  tasksReducer,
  Panel,
  PlaygroundManager,
  PlaygroundManagerContext,
  usePlaygroundManager,
} from '../../../../utils/playground-manager'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {mockGettingStarted, mockModel, mockModelInputSchema, mockModelState} from '../../__tests__/mocks'
import {fireFileDropEvent, testFile} from './test-utils'
import {getImageModelState, mockStoredMessage} from './mocks'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import type {ModelState} from '../../../../types'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import {defaultResponseFormat} from '../../../../utils/model-state'

const mockLocalStorage = {
  modelName: mockModel.name,
  messages: [mockStoredMessage],
}

const playgroundUrl = ModelUrlHelper.playgroundUrl(mockModelState.catalogData)

const getProps = (props: Partial<PlaygroundProps> = {}): PlaygroundProps => ({
  modelState: mockModelState,
  position: Panel.Main,
  onComparisonMode: false,
  canUseO1Models: false,
  modelClient: new AzureModelClient(playgroundUrl),
  ...props,
})

const PlaygroundWrapper = ({children}: PropsWithChildren) => {
  const [playgroundState, playgroundDispatch] = useReducer(tasksReducer, initialPlaygroundState())

  // Ensure PlaygroundManager is not recreated on every render
  const manager = useMemo(() => new PlaygroundManager(playgroundDispatch), [playgroundDispatch])

  return (
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerContext.Provider value={manager}>{children}</PlaygroundManagerContext.Provider>
    </PlaygroundStateProvider>
  )
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('Playground', () => {
  const safeLocalStorage = safeStorage('localStorage')
  afterEach(() => {
    safeLocalStorage.removeItem('playground-chat-messages')
  })

  test('displays no messages when page is loaded', () => {
    render(
      <PlaygroundWrapper>
        <Playground {...getProps()} />
      </PlaygroundWrapper>,
    )

    expect(screen.queryByTestId('playground-chat-message')).not.toBeInTheDocument()
  })

  test('displays the restore chat history button when there are messages stored in the local storage', () => {
    const modelState = {
      catalogData: mockModel,
      modelInputSchema: mockModelInputSchema,
      gettingStarted: mockGettingStarted,
      messages: [],
      isLoading: false,
      systemPrompt: '',
      isUseIndexSelected: false,
      chatInput: '',
      chatClosed: true,
      responseFormat: defaultResponseFormat,
      parameters: {},
      parametersHasChanges: false,
    }

    safeLocalStorage.setItem('playground-chat-messages', JSON.stringify(mockLocalStorage))
    render(
      <PlaygroundWrapper>
        <Playground {...getProps({modelState})} />
      </PlaygroundWrapper>,
    )

    expect(screen.getByTestId('restore-history-button')).toBeInTheDocument()
    expect(screen.queryByText('Reset chat history')).not.toBeInTheDocument()
  })

  test('does not display the restore chat history button when there are no messages stored in the local storage', async () => {
    render(
      <PlaygroundWrapper>
        <Playground {...getProps()} />
      </PlaygroundWrapper>,
    )

    expect(screen.queryByTestId('restore-history-button')).not.toBeInTheDocument()
  })

  test('reset chat history button is disabled when there are no messages that can be removed', () => {
    render(
      <PlaygroundWrapper>
        <Playground {...getProps()} />
      </PlaygroundWrapper>,
    )

    expect(screen.getByLabelText('Reset chat history')).toBeDisabled()
  })

  test('reset chat history button is not disabled when there are messages that can be removed', () => {
    const modelState = {...mockModelState, messages: [mockStoredMessage]}
    render(
      <PlaygroundWrapper>
        <Playground {...getProps({modelState})} />
      </PlaygroundWrapper>,
    )

    expect(screen.queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Reset chat history')).not.toBeDisabled()
  })

  test('clears messages in the local storage when the reset chat history button is clicked', () => {
    safeLocalStorage.setItem('playground-chat-messages', JSON.stringify(mockLocalStorage))
    const modelState = {...mockModelState, messages: [mockStoredMessage]}
    render(
      <PlaygroundWrapper>
        <Playground {...getProps({modelState})} />
      </PlaygroundWrapper>,
    )

    expect(localStorage.getItem('playground-chat-messages')).not.toBeNull()

    const resetButton = screen.getByRole('button', {name: 'Reset chat history'}) // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(resetButton)

    expect(localStorage.getItem('playground-chat-messages')).toBeNull()
  })

  test('display sample message in the chat window', () => {
    render(
      <PlaygroundWrapper>
        <Playground {...getProps()} />
      </PlaygroundWrapper>,
    )

    expect(screen.getByText('sample message')).toBeInTheDocument()
    expect(screen.queryByTestId('playground-chat-message')).not.toBeInTheDocument()
  })

  describe('attachments', () => {
    function testRender(modelState = getImageModelState(mockModelState)) {
      render(
        <PlaygroundWrapper>
          <Playground {...getProps({modelState})} />
        </PlaygroundWrapper>,
      )
    }

    test('renders the dropzone', () => {
      testRender()
      expect(screen.getByTestId('playground-chat-attachment-dropzone')).toBeInTheDocument()
    })

    test('does not render the dropzone when the model does not support images', () => {
      testRender(mockModelState)
      expect(screen.queryByTestId('playground-chat-attachment-dropzone')).not.toBeInTheDocument()
    })

    test('renders an attachment when one is added', async () => {
      testRender()
      const el = screen.getByTestId('playground-chat-attachment-dropzone')
      fireFileDropEvent([testFile()], el)
      expect(await screen.findByAltText('attachment')).toBeInTheDocument()
    })

    describe('on comparison mode', () => {
      const testClient = new AzureModelClient(playgroundUrl)

      function CurrentManager(props: {cb(m: PlaygroundManager): void}) {
        const manager = usePlaygroundManager()
        props.cb(manager)
        return null
      }

      function renderMockedComparisonMode(modelState: [ModelState, ModelState]) {
        let manager: PlaygroundManager | null = null

        const {user} = render(
          <PlaygroundWrapper>
            <CurrentManager cb={m => (manager = m)} />
            <Playground
              onComparisonMode
              modelClient={testClient}
              position={0}
              modelState={modelState[0]}
              canUseO1Models
            />
            <Playground
              onComparisonMode
              modelClient={testClient}
              position={1}
              modelState={modelState[1]}
              canUseO1Models
            />
          </PlaygroundWrapper>,
        )

        return {
          get user() {
            return user
          },
          get manager() {
            return manager
          },
        }
      }

      test('syncs inputs when sync inputs is on', async () => {
        const imageModelState = getImageModelState(mockModelState)

        // eslint-disable-next-line testing-library/render-result-naming-convention
        const result = renderMockedComparisonMode([imageModelState, imageModelState])

        act(() => {
          result.manager?.setSyncInputs(true)
        })

        const el = screen.getAllByTestId('playground-chat-attachment-dropzone')
        expect(el.length).toBe(2)

        fireFileDropEvent([testFile()], el.at(0))
        const attachments = await screen.findAllByAltText('attachment')
        expect(attachments).toHaveLength(2)
      })

      test('does not sync inputs when sync inputs is off', async () => {
        const imageModelState = getImageModelState(mockModelState)

        // eslint-disable-next-line testing-library/render-result-naming-convention
        const result = renderMockedComparisonMode([imageModelState, imageModelState])

        act(() => {
          result.manager?.setSyncInputs(false)
        })

        const el = screen.getAllByTestId('playground-chat-attachment-dropzone')
        expect(el.length).toBe(2)

        fireFileDropEvent([testFile('test')], el.at(0))
        let attachments = await screen.findAllByAltText('attachment')
        expect(attachments).toHaveLength(1)

        fireFileDropEvent([testFile('test2')], el.at(1))

        // There is a suspense boundary, which testing-library is not aware of. The `getAllByAltText` seems to cache
        // results. Since we expect attachments to be 2, let's wait for it.
        await waitFor(
          () => {
            attachments = screen.getAllByAltText('attachment')
            expect(attachments).toHaveLength(2)
          },
          {
            container: el.at(1),
          },
        )
      })

      test('syncs inputs, when sync inputs is toggled', async () => {
        const imageModelState = getImageModelState(mockModelState)

        // eslint-disable-next-line testing-library/render-result-naming-convention
        const result = renderMockedComparisonMode([imageModelState, imageModelState])

        act(() => {
          result.manager?.setSyncInputs(false)
        })

        const el = screen.getAllByTestId('playground-chat-attachment-dropzone')
        fireFileDropEvent([testFile()], el.at(0))
        let attachments = await screen.findAllByAltText('attachment')
        expect(attachments).toHaveLength(1)

        act(() => {
          result.manager?.setSyncInputs(true)
        })

        // Since we add ONE new file to the first input, it should be added to the second input as well
        fireFileDropEvent([testFile()], el.at(0))
        attachments = await screen.findAllByAltText('attachment')
        // Hence we're rendering 2 attachments now
        expect(attachments).toHaveLength(2)
      })

      test('when not syncing inputs and an attachment is removed, it should be removed from that one', async () => {
        const imageModelState = getImageModelState(mockModelState)

        // eslint-disable-next-line testing-library/render-result-naming-convention
        const result = renderMockedComparisonMode([imageModelState, imageModelState])

        act(() => {
          result.manager?.setSyncInputs(false)
        })

        const el = screen.getAllByTestId('playground-chat-attachment-dropzone')
        expect(el.length).toBe(2)

        fireFileDropEvent([testFile()], el.at(0))
        fireFileDropEvent([testFile()], el.at(1))
        const attachments = await screen.findAllByAltText('attachment')
        expect(attachments).toHaveLength(2)

        const removeButton = within(el.at(1)!).getByLabelText('Remove file', {selector: 'Button'})
        await result.user.click(removeButton)

        expect(within(el.at(0)!).getByAltText('attachment')).toBeInTheDocument()
        expect(within(el.at(1)!).queryByAltText('attachment')).not.toBeInTheDocument()
      })

      test('when syncing inputs and an attachment is removed, it should be removed from both', async () => {
        const imageModelState = getImageModelState(mockModelState)

        // eslint-disable-next-line testing-library/render-result-naming-convention
        const result = renderMockedComparisonMode([imageModelState, imageModelState])

        act(() => {
          result.manager?.setSyncInputs(true)
        })

        const el = screen.getAllByTestId('playground-chat-attachment-dropzone')
        expect(el.length).toBe(2)

        fireFileDropEvent([testFile()], el.at(0))
        const attachments = await screen.findAllByAltText('attachment')
        expect(attachments).toHaveLength(2)

        const removeButton = within(el.at(1)!).getByLabelText('Remove file', {selector: 'Button'})
        await result.user.click(removeButton)

        expect(screen.queryByAltText('attachment')).not.toBeInTheDocument()
      })
    })
  })
})
