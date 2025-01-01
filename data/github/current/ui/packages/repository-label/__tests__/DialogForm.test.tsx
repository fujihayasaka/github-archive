import {DialogForm} from '../DialogForm'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

import {LABELS} from '../constants/labels'
import type {SafeHTMLString} from '@github-ui/safe-html'

describe('DialogForm', () => {
  const mockOnDialogClose = jest.fn()
  const mockOnDialogSubmit = jest.fn()
  const mockSetIsSubmitting = jest.fn()

  const defaultProps = {
    onDialogClose: mockOnDialogClose,
    onDialogSubmit: mockOnDialogSubmit,
    formTitle: LABELS.newLabel,
  }

  beforeEach(() => {
    mockOnDialogClose.mockClear()
    mockOnDialogSubmit.mockClear()
    mockSetIsSubmitting.mockClear()
  })

  test('renders with empty form fields when no initial values are provided', () => {
    render(<DialogForm {...defaultProps} />)

    expect(screen.getByLabelText(LABELS.name)).toBeInTheDocument()
    expect(screen.getByLabelText(LABELS.description)).toBeInTheDocument()
    expect(screen.getByLabelText(LABELS.color)).toBeInTheDocument()

    expect(screen.getByLabelText(LABELS.name)).toHaveValue('')
    expect(screen.getByLabelText(LABELS.description)).toHaveValue('')

    expect(screen.getByRole('button', {name: LABELS.cancelButtonText})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`})).toBeInTheDocument()
  })

  test('renders with provided initial values', () => {
    const initialValues = {
      name: 'bug',
      nameHTML: 'bug' as SafeHTMLString,
      description: 'Something is not working',
      color: 'ff0000',
    }

    render(<DialogForm {...defaultProps} initialValues={initialValues} />)

    expect(screen.getByLabelText(LABELS.name)).toHaveValue('bug')
    expect(screen.getByLabelText(LABELS.description)).toHaveValue('Something is not working')

    const colorInput = screen.getByLabelText(LABELS.color)
    expect(colorInput).toHaveValue('#ff0000')
  })

  test('displays custom submit button text when provided', () => {
    render(<DialogForm {...defaultProps} submitButtonText="Create thing" />)

    expect(screen.getByRole('button', {name: `Create thing ( control enter )`})).toBeInTheDocument()
  })

  test('calls onDialogClose when cancel button is clicked', async () => {
    const {user} = render(<DialogForm {...defaultProps} />)

    await user.click(screen.getByRole('button', {name: LABELS.cancelButtonText}))

    expect(mockOnDialogClose).toHaveBeenCalledTimes(1)
  })

  test('validates name field is required on submit', async () => {
    const {user} = render(<DialogForm {...defaultProps} />)

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(screen.getByText(LABELS.nameRequired)).toBeInTheDocument()
    expect(mockOnDialogSubmit).not.toHaveBeenCalled()
  })

  test('validates color field format on submit', async () => {
    const {user} = render(<DialogForm {...defaultProps} />)

    await user.type(screen.getByLabelText(LABELS.name), 'bug')

    const colorInput = screen.getByLabelText(LABELS.color)
    await user.clear(colorInput)
    await user.type(colorInput, 'invalid-color')

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(screen.getByText(LABELS.invalidColor)).toBeInTheDocument()
    expect(mockOnDialogSubmit).not.toHaveBeenCalled()
  })

  test('calls onDialogSubmit with correct data when form is valid', async () => {
    const {user} = render(<DialogForm {...defaultProps} />)

    await user.type(screen.getByLabelText(LABELS.name), 'bug')
    await user.type(screen.getByLabelText(LABELS.description), 'Something is not working')
    await user.clear(screen.getByLabelText(LABELS.color))
    await user.type(screen.getByLabelText(LABELS.color), '#ffffff')

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(mockOnDialogSubmit).toHaveBeenCalledTimes(1)
    expect(mockOnDialogSubmit).toHaveBeenCalledWith(
      {
        name: 'bug',
        description: 'Something is not working',
        color: 'ffffff',
      },
      expect.any(Function),
    )
  })

  test('displays submission errors when provided', () => {
    const submissionErrors = 'The name "bug" is already in use'

    render(<DialogForm {...defaultProps} submissionErrors={submissionErrors} />)

    expect(screen.getByText(submissionErrors)).toBeInTheDocument()
    expect(screen.getByRole('alert')).toBeInTheDocument()
  })

  test('shows loading state during submission', async () => {
    const mockSubmitWithLoading = jest.fn((data, setIsSubmitting) => {
      setIsSubmitting(true)
    })

    const {user} = render(<DialogForm {...defaultProps} onDialogSubmit={mockSubmitWithLoading} />)

    await user.type(screen.getByLabelText(LABELS.name), 'bug')

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    const submitButton = screen.getByRole('button', {name: 'Create label'})
    expect(submitButton).toHaveAttribute('data-loading', 'true')
  })

  test('trims whitespace from input values before submission', async () => {
    const {user} = render(<DialogForm {...defaultProps} />)

    await user.type(screen.getByLabelText(LABELS.name), '  bug  ')
    await user.type(screen.getByLabelText(LABELS.description), '  Description with spaces  ')
    await user.clear(screen.getByLabelText(LABELS.color))
    await user.type(screen.getByLabelText(LABELS.color), '#ffffff')

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(mockOnDialogSubmit).toHaveBeenCalledWith(
      {
        name: 'bug',
        description: 'Description with spaces',
        color: 'ffffff',
      },
      expect.any(Function),
    )
  })
})
