import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockEvaluatorLLM} from '../../../../../test-utils/mock-data'
import {SystemPromptControl} from '../SystemPromptControl'

const updateEvaluator = jest.fn().mockName('updateEvaluator')

describe('SystemPromptControl', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders in readonly mode', () => {
    const systemPrompt = 'My fancy system prompt'
    const e = mockEvaluatorLLM({systemPrompt})

    render(<SystemPromptControl e={e} readonly updateEvaluator={updateEvaluator} />)

    const input = screen.getByRole('textbox', {name: 'System prompt'})
    expect(input).toBeInTheDocument()
    expect(input).toBeDisabled()
    expect(input).toHaveValue(systemPrompt)
    expect(updateEvaluator).not.toHaveBeenCalled()
  })

  it('renders in writable mode', async () => {
    const systemPrompt = 'My fancy system prompt'
    const e = mockEvaluatorLLM({systemPrompt})

    const {user} = render(<SystemPromptControl e={e} readonly={false} updateEvaluator={updateEvaluator} />)

    const input = screen.getByRole('textbox', {name: 'System prompt'})
    expect(input).toBeInTheDocument()
    expect(input).toBeEnabled()
    expect(input).toHaveValue(systemPrompt)

    await user.clear(input)

    expect(updateEvaluator).toHaveBeenCalledTimes(1)
    expect(updateEvaluator).toHaveBeenCalledWith({
      ...e,
      systemPrompt: undefined,
    })
  })
})
