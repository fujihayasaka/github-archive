import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockEvaluatorLLM} from '../../../../../test-utils/mock-data'
import {PromptControl} from '../PromptControl'

const updateEvaluator = jest.fn().mockName('updateEvaluator')

describe('PromptControl', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders in readonly mode', () => {
    const prompt = 'Some prompt of mine'
    const e = mockEvaluatorLLM({prompt})

    render(<PromptControl e={e} readonly updateEvaluator={updateEvaluator} />)

    const input = screen.getByRole('textbox', {name: 'Prompt *'})
    expect(input).toBeInTheDocument()
    expect(input).toBeDisabled()
    expect(input).toHaveAttribute('aria-required', 'true')
    expect(input).toHaveValue(prompt)
    expect(updateEvaluator).not.toHaveBeenCalled()
  })

  it('renders in writable mode', async () => {
    const prompt = 'Some prompt of mine'
    const e = mockEvaluatorLLM({prompt})

    const {user} = render(<PromptControl e={e} readonly={false} updateEvaluator={updateEvaluator} />)

    const input = screen.getByRole('textbox', {name: 'Prompt *'})
    expect(input).toBeInTheDocument()
    expect(input).toBeEnabled()
    expect(input).toHaveAttribute('aria-required', 'true')
    expect(input).toHaveValue(prompt)
    expect(updateEvaluator).not.toHaveBeenCalled()

    await user.clear(input)

    expect(updateEvaluator).toHaveBeenCalledTimes(1)
    expect(updateEvaluator).toHaveBeenCalledWith({
      ...e,
      prompt: '',
    })
  })
})
