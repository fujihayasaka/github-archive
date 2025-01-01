import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundNumericInput} from '../PlaygroundNumericInput'
import type {ModelParameterValue} from '../../../../types'

describe('PlaygroundNumericInput', () => {
  const onChange = jest.fn().mockName('onChange')
  const handleInputChange = jest.fn().mockName('handleInputChange')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when the value does not have a defined range', async () => {
    const name = 'some-neat-name'
    const label = 'This label will not be rendered'
    const value: ModelParameterValue = 200

    const {container, user} = render(
      <PlaygroundNumericInput
        name={name}
        label={label}
        value={value}
        onChange={onChange}
        handleInputChange={handleInputChange}
      />,
    )

    const numberInput = within(container).getByRole('spinbutton', {name: label})
    expect(numberInput).toHaveValue(value)
    expect(numberInput).not.toHaveAttribute('min')
    expect(numberInput).not.toHaveAttribute('max')
    expect(within(container).queryByRole('slider', {name: `${label} slider`})).not.toBeInTheDocument()
    expect(onChange).not.toHaveBeenCalled()
    expect(handleInputChange).not.toHaveBeenCalled()

    const newInput = '300'
    await user.type(numberInput, newInput)

    expect(onChange).toHaveBeenCalledTimes(newInput.length)
    expect(handleInputChange).not.toHaveBeenCalled()

    await user.click(container) // trigger onBlur handler for numberInput

    expect(handleInputChange).toHaveBeenCalledTimes(1)
  })

  test('renders when the value has a defined range', async () => {
    const name = 'MaxTemperaturePointDifferentialThingy'
    const min = 123
    const max = 456
    const value: ModelParameterValue = 200

    const {container, user} = render(
      <PlaygroundNumericInput
        name={name}
        min={min}
        max={max}
        value={value}
        onChange={onChange}
        handleInputChange={handleInputChange}
      />,
    )

    const numberInput = within(container).getByRole('spinbutton', {name})
    expect(numberInput).toHaveValue(value)
    expect(numberInput).toHaveAttribute('min', min.toString())
    expect(numberInput).toHaveAttribute('max', max.toString())
    const rangeInput = within(container).getByRole('slider', {name: `${name} slider`})
    expect(rangeInput).toHaveValue(value.toString())
    expect(rangeInput).toHaveAttribute('min', min.toString())
    expect(rangeInput).toHaveAttribute('max', max.toString())
    expect(onChange).not.toHaveBeenCalled()
    expect(handleInputChange).not.toHaveBeenCalled()

    const newInput = '300'
    await user.type(numberInput, newInput)

    expect(onChange).toHaveBeenCalledTimes(newInput.length)
    expect(handleInputChange).not.toHaveBeenCalled()

    await user.click(rangeInput) // trigger onBlur handler for numberInput

    expect(handleInputChange).toHaveBeenCalledTimes(1)
  })
})
