import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {DESCRIPTION_MAX_SIZE, NAME_MAX_SIZE, PresetDialog, type PresetDialogProps} from '../PresetDialog'
import {mockPreset} from '../../../__tests__/mocks'

afterEach(() => {
  jest.clearAllMocks()
})

describe('PresetDialog', () => {
  const onClose = jest.fn()
  const onSubmit = jest.fn()

  const defaultProps = {
    onClose,
    onSubmit,
    selectedPreset: mockPreset,
    action: 'create',
  } satisfies PresetDialogProps

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('loads PresetDialog with Cancel and Create preset footer buttons', () => {
    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={null} action="create" />)

    expect(screen.getByTestId('save-preset-dialog')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Create preset'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Update preset'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Create new preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Create new preset'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Name *'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Description'})).toBeInTheDocument()
    const saveChatHistoryCheckbox = screen.getByRole('checkbox', {name: 'Save chat history'})
    expect(saveChatHistoryCheckbox).toBeInTheDocument()
    expect(saveChatHistoryCheckbox).not.toBeChecked()
    const enableSharingCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(enableSharingCheckbox).toBeInTheDocument()
    expect(enableSharingCheckbox).not.toBeChecked()
    expect(onClose).not.toHaveBeenCalled()
    expect(onSubmit).not.toHaveBeenCalled()
  })

  test('loads PresetDialog with Cancel and Update preset footer buttons', () => {
    const selectedPreset = Object.assign({}, mockPreset)
    selectedPreset.includeChatHistory = true
    selectedPreset.private = false

    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={selectedPreset} action="update" />)

    expect(screen.getByTestId('save-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Update preset'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Create preset'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Edit preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Edit preset'})).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(nameInput).toHaveValue(selectedPreset.name)
    const descriptionInput = screen.getByRole('textbox', {name: 'Description'})
    expect(descriptionInput).toBeInTheDocument()
    expect(descriptionInput).toHaveValue(selectedPreset.description)
    const saveChatHistoryCheckbox = screen.getByRole('checkbox', {name: 'Save chat history'})
    expect(saveChatHistoryCheckbox).toBeInTheDocument()
    expect(saveChatHistoryCheckbox).not.toBeChecked() // should be unchecked because we ignore given preset value
    const enableSharingCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(enableSharingCheckbox).toBeInTheDocument()
    expect(enableSharingCheckbox).toBeChecked()
    expect(onClose).not.toHaveBeenCalled()
    expect(onSubmit).not.toHaveBeenCalled()
  })

  test('loads PresetDialog with name form input and existing preset value', () => {
    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={mockPreset} action="update" />)

    // Name is required with a * in the label
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(nameInput).toHaveAttribute('id', 'preset-name-input')
    expect(nameInput).toHaveAttribute('name', 'name')
    expect(nameInput).toHaveAttribute('placeholder', '')
    expect(nameInput).toHaveAttribute('value', mockPreset.name)
  })

  test('loads PresetDialog with description form input and existing preset value', () => {
    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={mockPreset} action="update" />)

    const descriptionInput = screen.getByRole('textbox', {name: 'Description'})
    expect(descriptionInput).toBeInTheDocument()
    expect(descriptionInput).toHaveAttribute('id', 'preset-description-input')
    expect(descriptionInput).toHaveAttribute('name', 'description')
    expect(descriptionInput).toHaveAttribute('placeholder', '')
    expect(descriptionInput).toHaveAttribute('value', mockPreset.description)
  })

  test('loads PresetDialog with includeChatHistory checkbox and initial false value', () => {
    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={mockPreset} action="update" />)

    const includeChatHistoryCheckbox = screen.getByRole('checkbox', {name: 'Save chat history'})
    expect(includeChatHistoryCheckbox).toBeInTheDocument()
    expect(includeChatHistoryCheckbox).toHaveAttribute('id', 'preset-include-chat-history-checkbox')
    expect(includeChatHistoryCheckbox).toHaveAttribute('name', 'includeChatHistory')
    expect(includeChatHistoryCheckbox).not.toHaveAttribute('checked')
  })

  test('loads PresetDialog with private checkbox and existing preset value', () => {
    const selectedPreset = Object.assign({}, mockPreset)
    selectedPreset.private = false

    render(<PresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={selectedPreset} action="update" />)

    const privateCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(privateCheckbox).toBeInTheDocument()
    expect(privateCheckbox).toHaveAttribute('id', 'preset-private-checkbox')
    expect(privateCheckbox).toHaveAttribute('name', 'private')
    expect(privateCheckbox).toHaveAttribute('checked')
  })

  describe('validating and submitting the form', () => {
    test('displays error when name field is empty', async () => {
      const {user} = render(<PresetDialog {...defaultProps} />)

      expect(screen.queryByText('Name is required')).not.toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.click(screen.getByRole('button', {name: 'Create preset'}))

      expect(screen.getByText('Name is required')).toBeInTheDocument()
    })

    test('displays error when name field is too long', async () => {
      const {user} = render(<PresetDialog {...defaultProps} />)

      expect(screen.queryByText('Name cannot be longer than 100 characters')).not.toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'a'.repeat(101))
      await user.click(screen.getByRole('button', {name: 'Create preset'}))

      expect(screen.getByText('Name cannot be longer than 100 characters')).toBeInTheDocument()
    })

    test('displays error when description field is too long', async () => {
      const {user} = render(<PresetDialog {...defaultProps} />)

      expect(screen.queryByText('Description cannot be longer than 255 characters')).not.toBeInTheDocument()

      const descriptionInput = screen.getByRole('textbox', {name: 'Description'})

      await user.clear(descriptionInput)
      await user.type(descriptionInput, 'a'.repeat(256))
      await user.click(screen.getByRole('button', {name: 'Create preset'}))

      expect(screen.getByText('Description cannot be longer than 255 characters')).toBeInTheDocument()
    })

    test('when name error is present, displays error message', async () => {
      render(<PresetDialog {...defaultProps} errors={{name: ['is already used']}} />)

      expect(screen.getByText('Name is already used')).toBeInTheDocument()
    })

    test('when url identifier error is present, displays error message', async () => {
      render(<PresetDialog {...defaultProps} errors={{url_identifier: 'is already taken'}} />)

      expect(screen.getByText('Name is already taken')).toBeInTheDocument()
    })

    test('calls onSubmit with the correct data when form is valid for preset creation', async () => {
      const {user} = render(<PresetDialog {...defaultProps} />)

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})
      const descriptionInput = screen.getByRole('textbox', {name: 'Description'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')
      await user.clear(descriptionInput)
      await user.type(descriptionInput, 'New preset description')
      await user.click(screen.getByRole('button', {name: 'Create preset'}))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({
        name: 'New preset name',
        description: 'New preset description',
        includeChatHistory: false,
        private: true,
        conversationHistory: [],
        parameters: {
          response_format: 'text',
        },
        urlIdentifier: '',
      })
      expect(onClose).not.toHaveBeenCalled()
    })
  })

  test('calls onSubmit with the correct data when form is valid for preset modification', async () => {
    const selectedPreset = Object.assign({}, mockPreset)
    selectedPreset.includeChatHistory = false
    selectedPreset.private = true

    const {user} = render(
      <PresetDialog action="update" selectedPreset={selectedPreset} onClose={onClose} onSubmit={onSubmit} />,
    )

    const updateButton = screen.getByRole('button', {name: 'Update preset'})
    expect(updateButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    const descriptionInput = screen.getByRole('textbox', {name: 'Description'})
    expect(descriptionInput).toBeInTheDocument()
    const saveChatHistoryCheckbox = screen.getByRole('checkbox', {name: 'Save chat history'})
    expect(saveChatHistoryCheckbox).toBeInTheDocument()
    expect(saveChatHistoryCheckbox).not.toBeChecked()
    const enableSharingCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(enableSharingCheckbox).toBeInTheDocument()
    expect(enableSharingCheckbox).not.toBeChecked()

    await user.clear(nameInput)
    await user.type(nameInput, 'new name')
    await user.clear(descriptionInput)
    await user.type(descriptionInput, 'new description')
    await user.click(saveChatHistoryCheckbox)
    await user.click(enableSharingCheckbox)
    await user.click(updateButton)

    expect(onSubmit).toHaveBeenCalledTimes(1)
    expect(onSubmit).toHaveBeenCalledWith({
      ...selectedPreset,
      name: 'new name',
      description: 'new description',
      private: false,
      conversationHistory: [],
      includeChatHistory: true,
      parameters: {
        response_format: 'text',
      },
    })
    expect(onClose).not.toHaveBeenCalled()
  })

  test('renders with update action with errors', () => {
    const errors = {url_identifier: 'is so bad'}

    render(
      <PresetDialog
        action="update"
        errors={errors}
        selectedPreset={mockPreset}
        onClose={onClose}
        onSubmit={onSubmit}
      />,
    )

    expect(screen.getByTestId('save-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Update preset'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Edit preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Edit preset'})).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(nameInput).toHaveAttribute('aria-invalid', 'true')
    expect(nameInput).toHaveValue(mockPreset.name)
    const ariaDescribedById = nameInput.getAttribute('aria-describedby')
    expect(ariaDescribedById).not.toBeNull()
    const errorMessageEl = screen.getByText('Name is so bad')
    expect(errorMessageEl).toBeInTheDocument()
    expect(errorMessageEl).toHaveAttribute('id', ariaDescribedById)
    expect(screen.getByRole('textbox', {name: 'Description'})).toBeInTheDocument()
    expect(screen.getByRole('checkbox', {name: 'Save chat history'})).toBeInTheDocument()
    expect(screen.getByRole('checkbox', {name: 'Enable sharing'})).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(onSubmit).not.toHaveBeenCalled()
  })

  test('validates name is not blank on submit', async () => {
    const {user} = render(
      <PresetDialog action="update" selectedPreset={mockPreset} onClose={onClose} onSubmit={onSubmit} />,
    )

    const updateButton = screen.getByRole('button', {name: 'Update preset'})
    expect(updateButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()

    await user.clear(nameInput) // wipe required field
    await user.click(updateButton)

    expect(onSubmit).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
    expect(nameInput).toHaveFocus()
    const ariaDescribedById = nameInput.getAttribute('aria-describedby')
    expect(ariaDescribedById).not.toBeNull()
    const errorMessageEl = screen.getByText('Name is required')
    expect(errorMessageEl).toBeInTheDocument()
    expect(errorMessageEl).toHaveAttribute('id', ariaDescribedById)
  })

  test('validates name is not too long on submit', async () => {
    const tooLongName = 'a'.repeat(NAME_MAX_SIZE + 1)

    const {user} = render(
      <PresetDialog action="update" selectedPreset={mockPreset} onClose={onClose} onSubmit={onSubmit} />,
    )

    const updateButton = screen.getByRole('button', {name: 'Update preset'})
    expect(updateButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()

    await user.clear(nameInput)
    await user.click(nameInput)
    await user.paste(tooLongName)
    await user.click(updateButton)

    expect(onSubmit).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
    expect(nameInput).toHaveFocus()
    expect(nameInput).toHaveAttribute('aria-invalid', 'true')
    const ariaDescribedById = nameInput.getAttribute('aria-describedby')
    expect(ariaDescribedById).not.toBeNull()
    const errorMessageEl = screen.getByText(`Name cannot be longer than ${NAME_MAX_SIZE} characters`)
    expect(errorMessageEl).toBeInTheDocument()
    expect(errorMessageEl).toHaveAttribute('id', ariaDescribedById)
  })

  test('validates description is not too long on submit', async () => {
    const tooLongDescription = 'a'.repeat(DESCRIPTION_MAX_SIZE + 1)

    const {user} = render(<PresetDialog action="create" selectedPreset={null} onClose={onClose} onSubmit={onSubmit} />)

    const createButton = screen.getByRole('button', {name: 'Create preset'})
    expect(createButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    const descriptionInput = screen.getByRole('textbox', {name: 'Description'})
    expect(descriptionInput).toBeInTheDocument()

    await user.type(nameInput, 'A Valid Name')
    await user.click(descriptionInput)
    await user.paste(tooLongDescription)
    await user.click(createButton)

    expect(onSubmit).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
    expect(descriptionInput).toHaveFocus()
    expect(descriptionInput).toHaveAttribute('aria-invalid', 'true')
    const ariaDescribedById = descriptionInput.getAttribute('aria-describedby')
    expect(ariaDescribedById).not.toBeNull()
    const errorMessageEl = screen.getByText(`Description cannot be longer than ${DESCRIPTION_MAX_SIZE} characters`)
    expect(errorMessageEl).toBeInTheDocument()
    expect(errorMessageEl).toHaveAttribute('id', ariaDescribedById)
  })
})
