import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import type {ComponentProps} from 'react'

import {CustomPropertyStringEditor} from '../CustomPropertyStringEditor'

const onChangeMock = jest.fn()

const sampleProps: ComponentProps<typeof CustomPropertyStringEditor> = {
  propertyValue: '',
  defaultValue: null,
  regexPattern: null,
  mixed: false,
  onChange: onChangeMock,
  orgName: 'acme',
}

beforeEach(() => {
  onChangeMock.mockClear()
})

describe('CustomPropertyStringEditor', () => {
  it('sets value', async () => {
    const {user} = render(<CustomPropertyStringEditor {...sampleProps} />)

    await user.click(screen.getByRole('button', {name: 'Set value'}))
    await user.type(getInput(), 'property-value')
    await user.click(getApplyButton())

    expect(onChangeMock).toHaveBeenCalledWith('property-value')
  })

  it('cancel does not update value', async () => {
    const {user} = render(<CustomPropertyStringEditor {...sampleProps} />)

    await user.click(screen.getByRole('button', {name: 'Set value'}))
    await user.type(getInput(), 'property-value')
    await user.click(withinDialog().getByRole('button', {name: 'Cancel'}))

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(onChangeMock).not.toHaveBeenCalled()
  })

  it('setting value to default sends empty value', async () => {
    const {user} = render(
      <CustomPropertyStringEditor {...sampleProps} propertyValue="manual-value" defaultValue="default-value" />,
    )

    await user.click(screen.getByRole('button', {name: 'manual-value'}))
    await user.click(withinDialog().getByRole('checkbox'))

    expect(withinDialog().getByRole('textbox')).toHaveValue('default-value')

    await user.click(getApplyButton())

    expect(onChangeMock).toHaveBeenCalledWith('')
  })

  it('checking default value updates input, manual editing unchecks default value', async () => {
    const {user} = render(
      <CustomPropertyStringEditor {...sampleProps} propertyValue="manual-value" defaultValue="default-value" />,
    )

    await user.click(screen.getByRole('button', {name: 'manual-value'}))
    await user.click(withinDialog().getByRole('checkbox'))

    expect(withinDialog().getByRole('textbox')).toHaveValue('default-value')

    await user.type(getInput(), 'new-value')

    expect(withinDialog().getByRole('checkbox')).not.toBeChecked()
  })

  it('prevents submitting and shows validation message if required value is empty', async () => {
    const {user} = render(
      <CustomPropertyStringEditor {...sampleProps} propertyValue="current-value" defaultValue="default-value" />,
    )

    await user.click(screen.getByRole('button', {name: 'current-value'}))
    await user.type(getInput(), 'property-value')
    await user.clear(getInput())

    await withinDialog().findByText('This property is required and can’t be blank')

    await user.click(getApplyButton())

    expect(getInput()).toHaveFocus()
    expect(onChangeMock).not.toHaveBeenCalled()
  })

  it('renders mixed value warning', async () => {
    const {user} = render(<CustomPropertyStringEditor {...sampleProps} mixed />)
    await user.click(screen.getByRole('button', {name: '(Mixed)'}))

    expect(withinDialog().getByText('Property has mixed values')).toBeInTheDocument()
  })
})

function withinDialog() {
  return within(screen.getByRole('dialog'))
}

function getInput() {
  return withinDialog().getByRole('textbox')
}

function getApplyButton() {
  return withinDialog().getByRole('button', {name: 'Apply'})
}
