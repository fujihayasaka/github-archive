import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ModelDetails} from '../ModelDetails'
import {mockModel} from '../../../routes/playground/__tests__/mocks'

describe('ModelDetails', () => {
  test('renders', () => {
    const model = Object.assign({}, mockModel, {
      training_data_date: undefined,
      max_input_tokens: 1500,
      max_output_tokens: 50001,
      rate_limit_tier: 'low',
    })

    const {container} = render(<ModelDetails model={model} />)

    const modelDetailsEl = within(container).getByTestId('model-details')
    expect(modelDetailsEl).toBeInTheDocument()
    expect(within(modelDetailsEl).getByTestId('context')).toHaveTextContent('2k input · 50k output')
    expect(within(modelDetailsEl).getByTestId('training-date')).toHaveTextContent('Undisclosed')
    expect(within(modelDetailsEl).getByRole('link', {name: 'Low'})).toBeInTheDocument()
    expect(within(modelDetailsEl).getByRole('link', {name: 'Azure support site'})).toBeInTheDocument()
  })

  test('renders when max output tokens is not specified', () => {
    const model = Object.assign({}, mockModel, {
      max_input_tokens: 3000,
      max_output_tokens: undefined,
    })

    const {container} = render(<ModelDetails model={model} />)

    const modelDetailsEl = within(container).getByTestId('model-details')
    expect(modelDetailsEl).toBeInTheDocument()
    expect(within(modelDetailsEl).getByTestId('context')).toHaveTextContent('3k input')
  })
})
