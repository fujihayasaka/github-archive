import {fireEvent, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundInput} from '../PlaygroundInput'
import {
  mockModelArrayInputSchemaParameter,
  mockModelBooleanInputSchemaParameter,
  mockModelIntegerInputSchemaParameter,
  mockModelNumericInputSchemaParameter,
  mockModelStringInputSchemaParameter,
} from '../../__tests__/mocks'
import type {ModelInputSchemaParameter, ModelParameterValue} from '../../../../types'

describe('PlaygroundInput', () => {
  const handleInputChange = jest.fn().mockName('handleInputChange')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders for integer parameter without min or max', async () => {
    const key = 'some-neat-key'
    const friendlyName = 'Hello world'
    const parameter = Object.assign({}, mockModelIntegerInputSchemaParameter, {
      key,
      friendlyName,
      min: undefined,
      max: undefined,
    })
    const value: ModelParameterValue = 124

    const {container, user} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    expect(handleInputChange).not.toHaveBeenCalled()
    const numberInput = within(container).getByRole('spinbutton', {name: friendlyName})
    expect(numberInput).toBeInTheDocument()
    expect(numberInput).not.toHaveAttribute('min')
    expect(numberInput).not.toHaveAttribute('max')
    expect(numberInput).toHaveValue(value)
    expect(numberInput).toHaveAttribute('type', 'number')
    expect(within(container).queryByRole('slider', {name: friendlyName})).not.toBeInTheDocument()

    await user.clear(numberInput)

    expect(handleInputChange).toHaveBeenCalledWith({key, value: '', validate: false})
  })

  test('renders for integer parameter with min and max', () => {
    const min = 123
    const max = 456
    const key = 'some-neat-key'
    const friendlyName = 'Hello world'
    const parameter = Object.assign({}, mockModelIntegerInputSchemaParameter, {
      key,
      friendlyName,
      default: max - 1,
      min,
      max,
    })
    const value: ModelParameterValue = 124

    const {container} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    expect(handleInputChange).not.toHaveBeenCalled()
    const numberInput = within(container).getByRole('spinbutton', {name: friendlyName})
    expect(numberInput).toBeInTheDocument()
    expect(numberInput).toHaveAttribute('min', min.toString())
    expect(numberInput).toHaveAttribute('max', max.toString())
    expect(numberInput).toHaveValue(value)
    const sliderInput = within(container).getByRole('slider', {name: `${friendlyName} slider`})
    expect(sliderInput).toBeInTheDocument()
    expect(sliderInput).toHaveAttribute('min', min.toString())
    expect(sliderInput).toHaveAttribute('max', max.toString())
    expect(sliderInput).toHaveValue(value.toString())

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(numberInput, {target: {value: '125'}})

    expect(handleInputChange).toHaveBeenCalledTimes(1)
    expect(handleInputChange).toHaveBeenCalledWith({key, value: '125', validate: false})
  })

  test('renders for numeric parameter', () => {
    const friendlyName = 'Temperature-ish'
    const min = 0
    const value: ModelParameterValue = 0.5
    const max = 1.0
    const key = 'tempValueRatingScore'
    const parameter = Object.assign({}, mockModelNumericInputSchemaParameter, {
      friendlyName,
      key,
      default: value,
      min,
      max,
    })

    const {container} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    expect(handleInputChange).not.toHaveBeenCalled()
    const numberInput = within(container).getByRole('spinbutton', {name: friendlyName})
    expect(numberInput).toBeInTheDocument()
    expect(numberInput).toHaveAttribute('min', min.toString())
    expect(numberInput).toHaveAttribute('max', max.toString())
    expect(numberInput).toHaveValue(value)
    const sliderInput = within(container).getByRole('slider', {name: `${friendlyName} slider`})
    expect(sliderInput).toBeInTheDocument()
    expect(sliderInput).toHaveAttribute('min', min.toString())
    expect(sliderInput).toHaveAttribute('max', max.toString())
    expect(sliderInput).toHaveValue(value.toString())

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(sliderInput, {target: {value: '0.75'}})

    expect(handleInputChange).toHaveBeenCalledWith({key, value: '0.75', validate: true})
  })

  test('renders for boolean parameter', async () => {
    const friendlyName = 'Jostle the flibble?'
    const key = 'jostle-flibble'
    const parameter: ModelInputSchemaParameter = Object.assign({}, mockModelBooleanInputSchemaParameter, {
      friendlyName,
      key,
    })
    const value: ModelParameterValue = true

    const {container, user} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    expect(handleInputChange).not.toHaveBeenCalled()
    const checkbox = within(container).getByRole('checkbox', {name: friendlyName})

    await user.click(checkbox)

    expect(handleInputChange).toHaveBeenCalledWith({key, value: false, validate: false})
  })

  test('renders for string parameter', async () => {
    const key = 'AVeryNiceFieldForThePeople'
    const parameter = Object.assign({}, mockModelStringInputSchemaParameter, {key})
    const value: ModelParameterValue = 'Simply the best value, marvelous.'

    const {container, user} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    const textInput = within(container).getByRole('textbox', {name: key})
    expect(textInput).toBeInTheDocument()
    expect(textInput).toHaveValue(value)
    expect(handleInputChange).not.toHaveBeenCalled()

    const newChars = 'wow'
    await user.type(textInput, newChars)

    expect(handleInputChange).toHaveBeenCalledTimes(newChars.length)
    expect(handleInputChange).toHaveBeenCalledWith({key, value: value + newChars.charAt(0), validate: false})
  })

  test('renders for array parameter', async () => {
    const key = 'someCoolArrayField'
    const parameter = Object.assign({}, mockModelArrayInputSchemaParameter, {key})
    const value: ModelParameterValue = ['coffee', 'tea', 'water']

    const {container, user} = render(
      <PlaygroundInput parameter={parameter} value={value} handleInputChange={handleInputChange} />,
    )

    const textarea = within(container).getByRole('textbox', {name: key})
    expect(textarea).toBeInTheDocument()
    expect(textarea).toHaveValue(value.join('\n'))
    expect(handleInputChange).not.toHaveBeenCalled()

    await user.clear(textarea)

    expect(handleInputChange).toHaveBeenCalledWith({key, value: [''], validate: false})
  })
})
