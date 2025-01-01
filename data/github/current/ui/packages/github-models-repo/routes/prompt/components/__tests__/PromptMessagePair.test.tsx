import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {messagePairLimit, PromptMessagePair} from '../PromptMessagePair'

const setMessagePairs = jest.fn().mockName('setMessagePairs')

describe('PromptMessagePair', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders add message pair button when no pairs exist', () => {
    render(<PromptMessagePair messagePairs={[]} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    expect(screen.getByRole('button', {name: 'Add message pair'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add message pair'})).not.toHaveAttribute('data-inactive')
  })

  test('renders inactive add message pair button when limit is reached', () => {
    const messagePairs = Array(messagePairLimit).fill({assistant: 'assistant text', user: 'user text'})
    render(<PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    expect(screen.getByRole('button', {name: 'Add message pair'})).toHaveAttribute('data-inactive', 'true')

    const tooltip = screen.getByText(`You can only have up to ${messagePairLimit} message pairs`)
    expect(tooltip).toHaveAttribute('role', 'tooltip')
    expect(tooltip).toBeInTheDocument()
  })

  test('creates new empty message pair when add button is clicked', async () => {
    const {user} = render(<PromptMessagePair messagePairs={[]} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    const addMessagePairButton = screen.getByRole('button', {name: 'Add message pair'})
    await user.click(addMessagePairButton)

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: '', user: ''}])
  })

  test('renders message pair with correct labels and inputs', () => {
    render(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant response', user: 'user question'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    expect(screen.getByTestId('remove-message-pair-0-assistant')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-0-user')).toBeInTheDocument()

    expect(screen.getByDisplayValue('assistant response')).toBeInTheDocument()
    expect(screen.getByDisplayValue('user question')).toBeInTheDocument()
  })

  test('removes message pair when remove button is clicked', async () => {
    const messagePairs = [
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 2', user: 'user 2'},
    ]
    const {user} = render(
      <PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    const removeButton = screen.getByTestId('remove-message-pair-0-assistant')
    await user.click(removeButton)

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: 'assistant 2', user: 'user 2'}])
  })

  test('updates user prompt when user input changes', async () => {
    const {user} = render(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant', user: 'user'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const userInput = screen.getByDisplayValue('user')
    await user.type(userInput, 's')

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: 'assistant', user: 'users'}])
  })

  test('updates assistant prompt when assistant input changes', async () => {
    const {user} = render(
      <PromptMessagePair
        messagePairs={[{assistant: 'assistant', user: 'user'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const assistantInput = screen.getByDisplayValue('assistant')
    await user.type(assistantInput, 's')

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: 'assistants', user: 'user'}])
  })

  test('renders multiple message pairs with correct remove buttons', () => {
    const messagePairs = [
      {assistant: 'response 1', user: 'question 1'},
      {assistant: 'response 2', user: 'question 2'},
      {assistant: 'response 3', user: 'question 3'},
    ]
    render(<PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    expect(screen.getByTestId('remove-message-pair-0-assistant')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-0-user')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-1-assistant')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-1-user')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-2-assistant')).toBeInTheDocument()
    expect(screen.getByTestId('remove-message-pair-2-user')).toBeInTheDocument()
  })

  test('handles empty message pairs correctly', () => {
    render(
      <PromptMessagePair
        messagePairs={[{assistant: '', user: ''}]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
      />,
    )

    const textareas = screen.getAllByRole('textbox')
    expect(textareas[0]).toHaveValue('')
    expect(textareas[1]).toHaveValue('')
  })

  test('passes variable keys to PromptAutocompleteInput components', () => {
    const variableKeys = ['input', 'username', 'context']
    render(
      <PromptMessagePair
        messagePairs={[{assistant: 'Hello {{username}}', user: 'Use {{input}} here'}]}
        setMessagePairs={setMessagePairs}
        variableKeys={variableKeys}
      />,
    )

    // Verify the inputs are rendered with the proper values
    expect(screen.getByDisplayValue('Hello {{username}}')).toBeInTheDocument()
    expect(screen.getByDisplayValue('Use {{input}} here')).toBeInTheDocument()
  })

  test('updates correct pair when multiple pairs exist', async () => {
    const messagePairs = [
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 2', user: 'user 2'},
    ]
    const {user} = render(
      <PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    // Get all assistant inputs and update the second one
    const assistantInputs = screen.getAllByDisplayValue(/^assistant/)
    await user.type(assistantInputs[1]!, 'x')

    // Should be called with the updated text at the end
    expect(setMessagePairs).toHaveBeenLastCalledWith([
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 2x', user: 'user 2'},
    ])
  })

  test('removes correct pair when multiple pairs exist', async () => {
    const messagePairs = [
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 2', user: 'user 2'},
      {assistant: 'assistant 3', user: 'user 3'},
    ]
    const {user} = render(
      <PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    // Remove the middle pair using the assistant remove button
    const removeButton = screen.getByTestId('remove-message-pair-1-assistant')
    await user.click(removeButton)

    expect(setMessagePairs).toHaveBeenCalledWith([
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 3', user: 'user 3'},
    ])
  })

  test('renders Variables button when onVariablesClick is provided', () => {
    const onVariablesClick = jest.fn()
    const VariablesIcon = () => <span>📚</span>

    render(
      <PromptMessagePair
        messagePairs={[]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
        onVariablesClick={onVariablesClick}
        variablesIcon={VariablesIcon}
      />,
    )

    expect(screen.getByTestId('edit-variables')).toBeInTheDocument()
    expect(screen.getByText('Variables')).toBeInTheDocument()
  })

  test('does not render Variables button when onVariablesClick is not provided', () => {
    render(<PromptMessagePair messagePairs={[]} setMessagePairs={setMessagePairs} variableKeys={[]} />)

    expect(screen.queryByTestId('edit-variables')).not.toBeInTheDocument()
  })

  test('calls onVariablesClick when Variables button is clicked', async () => {
    const onVariablesClick = jest.fn()
    const VariablesIcon = () => <span>📚</span>
    const {user} = render(
      <PromptMessagePair
        messagePairs={[]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
        onVariablesClick={onVariablesClick}
        variablesIcon={VariablesIcon}
      />,
    )

    const variablesButton = screen.getByTestId('edit-variables')
    await user.click(variablesButton)

    expect(onVariablesClick).toHaveBeenCalledTimes(1)
  })

  test('renders both Variables and Add message pair buttons side-by-side', () => {
    const onVariablesClick = jest.fn()
    const VariablesIcon = () => <span>📚</span>

    render(
      <PromptMessagePair
        messagePairs={[]}
        setMessagePairs={setMessagePairs}
        variableKeys={[]}
        onVariablesClick={onVariablesClick}
        variablesIcon={VariablesIcon}
      />,
    )

    const variablesButton = screen.getByTestId('edit-variables')
    const addButton = screen.getByRole('button', {name: 'Add message pair'})

    expect(variablesButton).toBeInTheDocument()
    expect(addButton).toBeInTheDocument()
  })

  test('removes message pair using user remove button', async () => {
    const messagePairs = [
      {assistant: 'assistant 1', user: 'user 1'},
      {assistant: 'assistant 2', user: 'user 2'},
    ]
    const {user} = render(
      <PromptMessagePair messagePairs={messagePairs} setMessagePairs={setMessagePairs} variableKeys={[]} />,
    )

    const removeButton = screen.getByTestId('remove-message-pair-0-user')
    await user.click(removeButton)

    expect(setMessagePairs).toHaveBeenCalledTimes(1)
    expect(setMessagePairs).toHaveBeenCalledWith([{assistant: 'assistant 2', user: 'user 2'}])
  })
})
