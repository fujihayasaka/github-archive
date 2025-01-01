import safeStorage from '@github-ui/safe-storage'
import {Playground, type PlaygroundProps} from '../Playground'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor, within} from '@testing-library/react'
import {useMemo, useReducer, type PropsWithChildren} from 'react'
import {testFile} from '@github-ui/attachments/test-utils'
import {tasksReducer, Panel, PlaygroundManager} from '../../../../utils/playground-manager'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {PlaygroundManagerProvider, usePlaygroundManager} from '../../../../contexts/PlaygroundManagerContext'
import {mockModelState} from '../../__tests__/mocks'
import {fireFileDropEvent} from './test-utils'
import {getImageModelState} from './mocks'
import type {ModelState} from '../../../../types'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import {ModelClientProvider} from '../../contexts/ModelClientContext'

const playgroundUrl = 'azure-ai-playground-url.com'

const getProps = (props: Partial<PlaygroundProps> = {}): PlaygroundProps => ({
  modelState: mockModelState,
  position: Panel.Main,
  ...props,
})

const PlaygroundWrapper = ({children}: PropsWithChildren) => {
  const [playgroundState, playgroundDispatch] = useReducer(tasksReducer, initialPlaygroundState())

  // Ensure PlaygroundManager is not recreated on every render
  const manager = useMemo(() => new PlaygroundManager(playgroundDispatch), [playgroundDispatch])
  const mockModelClient = new AzureModelClient(playgroundUrl)
  return (
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerProvider manager={manager}>
        <ModelClientProvider modelClient={mockModelClient}>{children}</ModelClientProvider>
      </PlaygroundManagerProvider>
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
            <Playground position={0} modelState={modelState[0]} />
            <Playground position={1} modelState={modelState[1]} />
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
