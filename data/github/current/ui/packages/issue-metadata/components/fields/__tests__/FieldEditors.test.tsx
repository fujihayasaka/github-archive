import {render, screen} from '@testing-library/react'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {IssueFieldTextEditor, IssueFieldSingleSelectEditor} from '../FieldEditors'

describe('IssueFieldTextEditor', () => {
  it('renders the text field with initial value', () => {
    const mockOnCommit = jest.fn()

    render(
      <IssueFieldTextEditor
        fieldId="text-field-1"
        fieldName="Description"
        initialValue="Initial text value"
        onCommit={mockOnCommit}
        hideDivider={false}
      />,
    )

    expect(screen.getByDisplayValue('Initial text value')).toBeInTheDocument()
    expect(screen.getByText('Description')).toBeInTheDocument()
  })

  it('updates text value when user types', async () => {
    const user = setupUserEvent()
    const mockOnCommit = jest.fn()

    render(
      <IssueFieldTextEditor
        fieldId="text-field-1"
        fieldName="Description"
        initialValue="Initial value"
        onCommit={mockOnCommit}
        hideDivider={false}
      />,
    )

    const textInput = screen.getByDisplayValue('Initial value')
    await user.clear(textInput)
    await user.type(textInput, 'New text value')

    expect(screen.getByDisplayValue('New text value')).toBeInTheDocument()
  })

  it('calls onCommit when input loses focus', async () => {
    const user = setupUserEvent()
    const mockOnCommit = jest.fn()

    render(
      <IssueFieldTextEditor
        fieldId="text-field-1"
        fieldName="Description"
        initialValue="Initial value"
        onCommit={mockOnCommit}
        hideDivider={false}
      />,
    )

    const textInput = screen.getByDisplayValue('Initial value')
    await user.clear(textInput)
    await user.type(textInput, 'Updated value')
    await user.tab() // trigger blur event

    expect(mockOnCommit).toHaveBeenCalledWith('text-field-1', 'Updated value')
  })
})

describe('IssueFieldSingleSelectEditor', () => {
  it('renders the single select field with selected value', () => {
    const mockOnCommit = jest.fn()
    const initialValue = {
      name: 'High',
      color: '#ff0000',
      description: 'High priority item',
    }

    render(
      <IssueFieldSingleSelectEditor
        fieldId="priority-field-1"
        fieldName="Priority"
        initialValue={initialValue}
        onCommit={mockOnCommit}
        hideDivider={false}
      />,
    )

    expect(screen.getByText('Priority')).toBeInTheDocument()
    expect(screen.getByText('High')).toBeInTheDocument()
  })

  it('renders with null initial value', () => {
    const mockOnCommit = jest.fn()

    render(
      <IssueFieldSingleSelectEditor
        fieldId="priority-field-1"
        fieldName="Priority"
        initialValue={null}
        onCommit={mockOnCommit}
        hideDivider={false}
      />,
    )

    expect(screen.getByText('Priority')).toBeInTheDocument()
    // When initialValue is null, the token should be present
    expect(screen.getByRole('button', {name: /edit priority/i})).toBeInTheDocument()
  })

  it('renders with hideDivider=true', () => {
    const mockOnCommit = jest.fn()

    render(
      <IssueFieldSingleSelectEditor
        fieldId="priority-field-1"
        fieldName="Priority"
        initialValue={null}
        onCommit={mockOnCommit}
        hideDivider
      />,
    )

    expect(screen.getByText('Priority')).toBeInTheDocument()
  })
})
