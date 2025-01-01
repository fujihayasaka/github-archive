import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundArrayInput} from '../PlaygroundArrayInput'
import type {ModelParameterValue} from '../../../../types'

describe('PlaygroundArrayInput', () => {
  const onChange = jest.fn().mockName('onChange')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders', async () => {
    const name = 'IAmTheKey'
    const value: ModelParameterValue = ['one', 'two', 'three']

    const {container, user} = render(<PlaygroundArrayInput name={name} value={value} onChange={onChange} />)

    const textarea = within(container).getByRole('textbox', {name})
    expect(textarea).toHaveValue('one\ntwo\nthree')
    expect(textarea).toHaveAttribute('name', name)
    expect(onChange).not.toHaveBeenCalled()

    const newInput = 'four'
    await user.type(textarea, newInput)

    expect(onChange).toHaveBeenCalledTimes(newInput.length)
  })
})
