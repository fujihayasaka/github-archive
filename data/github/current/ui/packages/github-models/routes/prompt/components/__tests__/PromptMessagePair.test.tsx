import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {messagePairLimit, PromptMessagePair} from '../PromptMessagePair'
import {PromptEvalsStateProvider} from '../../contexts/PromptEvalsStateContext'
import type {PromptEvalsManager} from '../../prompt-evals-manager'
import {PromptEvalsManagerContext} from '../../prompt-evals-manager'
import {mockPromptEvalsState} from './mocks'
import type {MessagePair} from '../../../../types'

const setMessagePairs = jest.fn().mockName('setMessagePairs')

describe('PromptMessagePair', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders add message pair button', () => {
    renderComponent(<PromptMessagePair messagePairs={[]} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    expect(screen.getByRole('button', {name: 'Add message pair'})).toBeInTheDocument()
  })

  test('renders inactive add message pair button if limit has been reached', () => {
    const messagePairs = Array(messagePairLimit).fill({assistant: 'assistant 1', user: 'user 1'})
    renderComponent(
      <PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    expect(screen.getByRole('button', {name: 'Add message pair'})).toHaveAttribute('data-inactive', 'true')

    const tooltip = screen.getByText(`You can only have up to ${messagePairLimit} message pairs`)
    expect(tooltip).toHaveAttribute('role', 'tooltip')
    expect(tooltip).toBeInTheDocument()
  })

  test('creates new user and assistant prompts when add message button is clicked', async () => {
    const {user} = renderComponent(
      <PromptMessagePair messagePairs={[]} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    const addMessagePairButton = screen.getByRole('button', {name: 'Add message pair'})
    expect(addMessagePairButton).toBeInTheDocument()

    await user.click(addMessagePairButton)

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: '', user: ''}])
  })

  test('renders with a message pair form when a message pair is provided', () => {
    renderComponent(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant', user: 'user'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    expect(screen.getByText('Pair 1')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-0')).toBeInTheDocument()

    expect(screen.getByRole('textbox', {name: 'Assistant'})).toHaveValue('assistant')
    expect(screen.getByRole('textbox', {name: 'User'})).toHaveValue('user')
  })

  test('removes a message pair when the remove button is clicked', async () => {
    const {user} = renderComponent(
      <PromptMessagePair
        messagePairs={[
          {assistant: 'assistant 1', user: 'user 1'},
          {assistant: 'assistant 2', user: 'user 2'},
        ]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const removeMessagePairButton = screen.getByTestId('remove-message-pair-0')
    await user.click(removeMessagePairButton)

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: 'assistant 2', user: 'user 2'}])
  })

  test('updates the user prompt when the user input is changed', async () => {
    const {user} = renderComponent(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant', user: 'user'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const userPromptInput = screen.getByRole('textbox', {name: 'User'})
    await user.type(userPromptInput, 's')

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{user: 'users', assistant: 'assistant'}])
  })

  test('updates the assistant prompt when the assistant input is changed', async () => {
    const {user} = renderComponent(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant', user: 'user'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const assistantPromptInput = screen.getByRole('textbox', {name: 'Assistant'})
    await user.type(assistantPromptInput, 's')

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{user: 'user', assistant: 'assistants'}])
  })
})

function renderComponent(component: JSX.Element, messagePairs: MessagePair[] = []) {
  const initialState = mockPromptEvalsState()
  const stateValue = {...initialState, model: {...initialState.model, messagePairs}}
  const manager = {} as PromptEvalsManager
  manager.setMessagePairs = setMessagePairs

  return render(
    <PromptEvalsStateProvider state={stateValue}>
      <PromptEvalsManagerContext.Provider value={manager}>{component}</PromptEvalsManagerContext.Provider>
    </PromptEvalsStateProvider>,
  )
}
