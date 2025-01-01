import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {NAME_MAX_SIZE, PresetDialog, type PresetDialogProps} from '../PresetDialog'
import {mockPreset} from '../../../__tests__/mocks'
import {mockModelState, mockPlaygroundState, mockStoredMessage} from '../../__tests__/mocks'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import type {PlaygroundState} from '../../../../../types'
import {getDefaultPreset} from '../PresetsMenu'

const mockCreatePreset = jest.fn().mockName('createPreset')
const mockUpdatePreset = jest.fn().mockName('updatePreset')

jest.mock('../../../../../utils/presets', () => ({
  ...jest.requireActual('../../../../../utils/presets'),
  createPreset: (...args: unknown[]) => mockCreatePreset(...args),
  updatePreset: (...args: unknown[]) => mockUpdatePreset(...args),
}))

afterEach(() => {
  jest.clearAllMocks()
})

describe('PresetDialog', () => {
  const onClose = jest.fn()
  const onSuccess = jest.fn()

  const defaultProps = () =>
    ({
      onClose,
      onSuccess,
      selectedPreset: {...mockPreset},
      action: 'create',
    }) satisfies PresetDialogProps

  test('loads PresetDialog with Cancel and Save prompt footer buttons', () => {
    render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={getDefaultPreset()} action="create" />)

    expect(screen.getByTestId('save-preset-dialog')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Save prompt'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Update prompt'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Create prompt'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Create prompt'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Name *'})).toBeInTheDocument()
    const enableSharingCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(enableSharingCheckbox).toBeInTheDocument()
    expect(enableSharingCheckbox).not.toBeChecked()
    expect(onClose).not.toHaveBeenCalled()
    expect(onSuccess).not.toHaveBeenCalled()
  })

  test('loads PresetDialog with Cancel and Update prompt footer buttons', () => {
    const selectedPreset = Object.assign({}, mockPreset)
    selectedPreset.private = false

    render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={selectedPreset} action="update" />)

    expect(screen.getByTestId('save-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Update prompt'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Save prompt'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Update prompt'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Update prompt'})).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(nameInput).toHaveValue(selectedPreset.name)
    const enableSharingCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(enableSharingCheckbox).toBeInTheDocument()
    expect(enableSharingCheckbox).toBeChecked()
    expect(onClose).not.toHaveBeenCalled()
    expect(onSuccess).not.toHaveBeenCalled()
  })

  test('loads PresetDialog with name form input and existing preset value', () => {
    render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} action="update" />)

    // Name is required with a * in the label
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(nameInput).toHaveAttribute('id', 'preset-name-input')
    expect(nameInput).toHaveAttribute('name', 'name')
    expect(nameInput).toHaveAttribute('placeholder', '')
    expect(nameInput).toHaveAttribute('value', mockPreset.name)
  })

  test('loads PresetDialog with public checkbox and existing preset value', () => {
    const selectedPreset = Object.assign({}, mockPreset)
    selectedPreset.private = false

    render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={selectedPreset} action="update" />)

    const publicCheckbox = screen.getByRole('checkbox', {name: 'Enable sharing'})
    expect(publicCheckbox).toBeInTheDocument()
    expect(publicCheckbox).toHaveAttribute('id', 'preset-public-checkbox')
    expect(publicCheckbox).toHaveAttribute('checked')
  })

  describe('displays appropriate checkboxes', () => {
    test('with system prompt, message, and chat inputs', () => {
      const modelState = mockModelState({
        systemPrompt: 'system prompt',
        chatInput: 'chat input',
        messages: [mockStoredMessage],
      })

      render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} action="update" />, {
        playgroundState: mockPlaygroundState({
          models: [modelState],
        }),
      })

      expect(screen.getByRole('checkbox', {name: 'System prompt'})).toBeInTheDocument()
      expect(screen.getByRole('checkbox', {name: 'Current input'})).toBeInTheDocument()
      expect(screen.getByRole('checkbox', {name: 'First message'})).toBeInTheDocument()
    })

    test('with only system prompt', () => {
      const modelState = mockModelState({
        systemPrompt: 'system prompt',
        chatInput: '',
        messages: [],
      })

      render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} action="update" />, {
        playgroundState: mockPlaygroundState({
          models: [modelState],
        }),
      })

      expect(screen.getByRole('checkbox', {name: 'System prompt'})).toBeInTheDocument()
      expect(screen.queryByRole('checkbox', {name: 'Current input'})).not.toBeInTheDocument()
      expect(screen.queryByRole('checkbox', {name: 'First message'})).not.toBeInTheDocument()
    })

    test('with only chat input', () => {
      const modelState = mockModelState({
        systemPrompt: '',
        chatInput: 'chat input',
        messages: [],
      })

      render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} action="update" />, {
        playgroundState: mockPlaygroundState({
          models: [modelState],
        }),
      })

      expect(screen.queryByRole('checkbox', {name: 'System prompt'})).not.toBeInTheDocument()
      expect(screen.getByRole('checkbox', {name: 'Current input'})).toBeInTheDocument()
      expect(screen.queryByRole('checkbox', {name: 'First message'})).not.toBeInTheDocument()
    })

    test('with only first message', () => {
      const modelState = mockModelState({
        systemPrompt: '',
        chatInput: '',
        messages: [mockStoredMessage],
      })

      render(<PresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} action="update" />, {
        playgroundState: mockPlaygroundState({
          models: [modelState],
        }),
      })

      expect(screen.queryByRole('checkbox', {name: 'System prompt'})).not.toBeInTheDocument()
      expect(screen.queryByRole('checkbox', {name: 'Current input'})).not.toBeInTheDocument()
      expect(screen.getByRole('checkbox', {name: 'First message'})).toBeInTheDocument()
    })
  })

  describe('validating and submitting the form', () => {
    test('displays error when name field is empty', async () => {
      const {user} = render(<PresetDialog {...defaultProps()} />)

      expect(screen.queryByText('Name is required')).not.toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.click(screen.getByRole('button', {name: 'Save prompt'}))

      expect(screen.getByText('Name is required')).toBeInTheDocument()
    })

    test('displays error when name field is too long', async () => {
      const {user} = render(<PresetDialog {...defaultProps()} />)

      expect(screen.queryByText('Name cannot be longer than 100 characters')).not.toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'a'.repeat(101))
      await user.click(screen.getByRole('button', {name: 'Save prompt'}))

      expect(screen.getByText('Name cannot be longer than 100 characters')).toBeInTheDocument()
    })

    test('calls createPreset with the correct data when form is valid for preset creation', async () => {
      mockCreatePreset.mockResolvedValue({ok: true, json: () => Promise.resolve({})})
      const {user} = render(<PresetDialog {...defaultProps()} />)

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')
      await user.click(screen.getByRole('button', {name: 'Save prompt'}))

      expect(mockCreatePreset).toHaveBeenCalledTimes(1)
      expect(mockCreatePreset).toHaveBeenCalledWith({
        preset: {
          name: 'New preset name',
          private: true,
          parameters: {
            system_prompt: mockModelState().systemPrompt,
            chat_prompt: '',
          },
        },
      })

      expect(onSuccess).toHaveBeenCalledTimes(1)
      expect(onClose).toHaveBeenCalledTimes(1)
    })

    test('displays errors when returned from createPreset', async () => {
      mockCreatePreset.mockResolvedValue({
        ok: false,
        json: () =>
          Promise.resolve({
            error: {
              name: ['is so bad'],
              error: 'generic error',
            },
          }),
      })
      const {user} = render(<PresetDialog {...defaultProps()} />)

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')
      await user.click(screen.getByRole('button', {name: 'Save prompt'}))

      expect(mockCreatePreset).toHaveBeenCalledTimes(1)
      expect(mockCreatePreset).toHaveBeenCalledWith({
        preset: {
          name: 'New preset name',
          private: true,
          parameters: {
            system_prompt: mockModelState().systemPrompt,
            chat_prompt: '',
          },
        },
      })

      expect(onSuccess).not.toHaveBeenCalled()
      expect(onClose).not.toHaveBeenCalled()

      expect(screen.getByText('Name is so bad')).toBeInTheDocument()
      expect(screen.getByText('generic error')).toBeInTheDocument()
    })

    test('displays errors when createPreset throws an error', async () => {
      mockCreatePreset.mockRejectedValue(new Error('oh no'))
      const {user} = render(<PresetDialog {...defaultProps()} />)

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')
      await user.click(screen.getByRole('button', {name: 'Save prompt'}))

      expect(mockCreatePreset).toHaveBeenCalledTimes(1)
      expect(mockCreatePreset).toHaveBeenCalledWith({
        preset: {
          name: 'New preset name',
          private: true,
          parameters: {
            system_prompt: mockModelState().systemPrompt,
            chat_prompt: '',
          },
        },
      })

      expect(onSuccess).not.toHaveBeenCalled()
      expect(onClose).not.toHaveBeenCalled()

      expect(screen.getByText('Failed to create preset: New preset name')).toBeInTheDocument()
    })

    test('displays errors when returned from updatePreset', async () => {
      mockUpdatePreset.mockResolvedValue({
        ok: false,
        json: () =>
          Promise.resolve({
            error: {
              name: ['is so bad'],
              error: 'generic error',
            },
          }),
      })
      const {user} = render(<PresetDialog {...defaultProps()} action="update" />)

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')
      await user.click(screen.getByRole('button', {name: 'Update prompt'}))

      expect(mockUpdatePreset).toHaveBeenCalledTimes(1)
      expect(mockUpdatePreset).toHaveBeenCalledWith({
        preset: {
          name: 'New preset name',
          private: true,
          parameters: {
            system_prompt: mockModelState().systemPrompt,
            chat_prompt: '',
          },
        },
        urlIdentifier: mockPreset.urlIdentifier,
      })

      expect(onSuccess).not.toHaveBeenCalled()
      expect(onClose).not.toHaveBeenCalled()

      expect(screen.getByText('Name is so bad')).toBeInTheDocument()
      expect(screen.getByText('generic error')).toBeInTheDocument()
    })
  })

  test('validates name is not blank on submit', async () => {
    const {user} = render(
      <PresetDialog action="update" selectedPreset={mockPreset} onClose={onClose} onSuccess={onSuccess} />,
    )

    const updateButton = screen.getByRole('button', {name: 'Update prompt'})
    expect(updateButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()

    await user.clear(nameInput) // wipe required field
    await user.click(updateButton)

    expect(onSuccess).not.toHaveBeenCalled()
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
      <PresetDialog action="update" selectedPreset={mockPreset} onClose={onClose} onSuccess={onSuccess} />,
    )

    const updateButton = screen.getByRole('button', {name: 'Update prompt'})
    expect(updateButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()

    await user.clear(nameInput)
    await user.click(nameInput)
    await user.paste(tooLongName)
    await user.click(updateButton)

    expect(onSuccess).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
    expect(nameInput).toHaveFocus()
    expect(nameInput).toHaveAttribute('aria-invalid', 'true')
    const ariaDescribedById = nameInput.getAttribute('aria-describedby')
    expect(ariaDescribedById).not.toBeNull()
    const errorMessageEl = screen.getByText(`Name cannot be longer than ${NAME_MAX_SIZE} characters`)
    expect(errorMessageEl).toBeInTheDocument()
    expect(errorMessageEl).toHaveAttribute('id', ariaDescribedById)
  })

  test('runs the close function when the close button is clicked', async () => {
    const {user} = render(<PresetDialog {...defaultProps()} />)

    expect(onClose).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', {name: 'Cancel'}))

    expect(onClose).toHaveBeenCalledTimes(1)
  })
})

function render(
  component: JSX.Element,
  {playgroundState, ...opts}: TestRenderOptions & {playgroundState?: PlaygroundState} = {},
) {
  return htmlRender(
    <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>{component}</PlaygroundStateProvider>,
    opts,
  )
}
