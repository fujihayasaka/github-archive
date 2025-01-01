import {fireEvent, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import FieldProgression from '../FieldProgression'
import type {FieldProgressionFieldProps} from '../FieldProgressionField'
import {FakeFieldProgressionEditComponent as FakeEditComponent} from './helpers/FakeFieldProgressionEditComponent'

describe('FieldProgression', () => {
  test('renders sequence of fields', () => {
    const fields: FieldProgressionFieldProps[] = [
      {
        name: 'firstField',
        displayValue: 'firstFieldValue',
        editComponent: <FakeEditComponent value="firstFieldValue" setValue={() => {}} />,
      },
      {
        name: 'secondField',
        displayValue: 'secondFieldValue',
        editComponent: <FakeEditComponent value="secondFieldValue" setValue={() => {}} />,
      },
    ]

    render(<FieldProgression fields={fields} currentFieldIndex={0} setCurrentFieldIndex={() => {}} />)

    const firstField = screen.getByTestId('field-progression-field-0')
    expect(firstField).toBeInTheDocument()
    const secondField = screen.getByTestId('field-progression-field-1')
    expect(secondField).toBeInTheDocument()
  })

  test('renders edit component for current field only', () => {
    const fields: FieldProgressionFieldProps[] = [
      {
        name: 'firstField',
        displayValue: 'firstFieldValue',
        editComponent: <FakeEditComponent value="firstFieldValue" setValue={() => {}} />,
      },
      {
        name: 'secondField',
        displayValue: 'secondFieldValue',
        editComponent: <FakeEditComponent value="secondFieldValue" setValue={() => {}} />,
      },
    ]

    render(<FieldProgression fields={fields} currentFieldIndex={0} setCurrentFieldIndex={() => {}} />)

    const firstField = screen.getByTestId('field-progression-field-0')
    const firstFieldInput = within(firstField).getByTestId('fake-edit-component-input')
    expect(firstFieldInput).toBeInTheDocument()

    const secondField = screen.getByTestId('field-progression-field-1')
    const secondFieldInput = within(secondField).queryByTestId('fake-edit-component-input')
    expect(secondFieldInput).not.toBeInTheDocument()
  })

  test('on save for first field in sequence, updates index and shows edit component for second field', () => {
    let currentFieldIndex = 0 // Simulate state for currentFieldIndex
    const mockSetCurrentFieldIndex = jest.fn(newIndex => {
      currentFieldIndex = newIndex // Update the simulated state
      rerenderComponent() // Rerender the component with the updated index
    })
    const fields: FieldProgressionFieldProps[] = [
      {
        name: 'firstField',
        displayValue: 'firstFieldValue',
        editComponent: <FakeEditComponent value="firstFieldValue" setValue={() => {}} />,
      },
      {
        name: 'secondField',
        displayValue: 'secondFieldValue',
        editComponent: <FakeEditComponent value="secondFieldValue" setValue={() => {}} />,
      },
    ]

    const {rerender} = render(
      <FieldProgression fields={fields} currentFieldIndex={0} setCurrentFieldIndex={mockSetCurrentFieldIndex} />,
    )

    const rerenderComponent = () => {
      rerender(
        <FieldProgression
          fields={fields}
          currentFieldIndex={currentFieldIndex}
          setCurrentFieldIndex={mockSetCurrentFieldIndex}
        />,
      )
    }

    const firstField = screen.getByTestId('field-progression-field-0')
    const firstFieldInput = within(firstField).getByTestId('fake-edit-component-input')
    const firstFieldButton = within(firstField).getByTestId('fake-edit-component-button')

    // update the first field and save it
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(firstFieldInput, {target: {value: 'some-value'}})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(firstFieldButton)

    // confirm the second field's edit component is now displayed
    const secondField = screen.getByTestId('field-progression-field-1')
    const secondFieldInput = within(secondField).queryByTestId('fake-edit-component-input')
    expect(secondFieldInput).toBeInTheDocument()

    // confirm the first first field is still displayed, but its edit component is not displayed
    expect(firstField).toBeInTheDocument()
    expect(firstFieldInput).not.toBeInTheDocument()
  })
})
