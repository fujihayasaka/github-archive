import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockModel, mockModels, mockPromptConfig, mockResizeObserver} from '../../../../test-utils/mock-data'
import type {RepoModel} from '../../../../types'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {PromptEditorDialog} from '../PromptEditorDialog'

const onSave = jest.fn().mockName('onSave')
const onClose = jest.fn().mockName('onClose')

describe('PromptEditorDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  // https://github.com/github/models/issues/1646
  it('renders for a new prompt and allows selecting a model', async () => {
    const primaryLabel = 'Create'
    jest.useFakeTimers()
    const modelToSelect = mockModels[0]!

    const {user} = render(<PromptEditorDialog onSave={onSave} onClose={onClose} primaryLabel={primaryLabel} />, {
      models: mockModels,
    })

    const dialog = screen.getByRole('dialog', {name: 'Edit prompt'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Edit prompt'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    const modelPickerToggle = within(dialog).getByRole('button', {name: 'Select model'})
    expect(modelPickerToggle).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Show parameters setting'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: primaryLabel})
    expect(submitButton).toBeInTheDocument()
    const userPromptInput = within(dialog).getByRole('textbox', {name: 'User prompt'})
    expect(userPromptInput).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select model'})).not.toBeInTheDocument()

    await user.click(modelPickerToggle)

    const modelPickerDialog = screen.getByRole('dialog', {name: 'Select model'})
    expect(modelPickerDialog).toBeInTheDocument()
    expect(within(modelPickerDialog).getByRole('heading', {name: 'Select model'})).toBeInTheDocument()
    expect(within(modelPickerDialog).getByRole('textbox', {name: 'Filter models'})).toBeInTheDocument()
    const modelsList = within(modelPickerDialog).getByRole('listbox', {name: 'Select model'})
    expect(modelsList).toBeInTheDocument()
    const modelOption = within(modelsList).getByRole('option', {name: modelToSelect.friendly_name})
    expect(modelOption).toBeInTheDocument()

    await user.click(modelOption)

    expect(screen.queryByRole('dialog', {name: 'Select model'})).not.toBeInTheDocument()
    expect(
      within(dialog).getByRole('button', {name: `${modelToSelect.publisher} logo ${modelToSelect.friendly_name}`}),
    ).toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: 'Select model'})).not.toBeInTheDocument()
    expect(onSave).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()

    await user.type(userPromptInput, 'tell me a story')
    await user.click(submitButton)

    expect(onSave).toHaveBeenCalledTimes(1)
    expect(onSave).toHaveBeenCalledWith({
      messages: [
        {message: '', role: 'system', timestamp: new Date()},
        {message: 'tell me a story', role: 'user', timestamp: new Date()},
      ],
      model: modelToSelect.original_name,
    })
  })

  it('renders for an existing prompt', async () => {
    const primaryLabel = 'Update'
    const model = mockModel()
    const prompt = mockPromptConfig({model: model.id})
    const models = mockModels.concat([model])

    const {user} = render(
      <PromptEditorDialog prompt={prompt} onSave={onSave} onClose={onClose} primaryLabel={primaryLabel} />,
      {models},
    )

    const dialog = screen.getByRole('dialog', {name: 'Edit prompt'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Edit prompt'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(
      within(dialog).getByRole('button', {name: `${model.publisher} logo ${model.friendly_name}`}),
    ).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Show parameters setting'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: primaryLabel})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'User prompt'})).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select model'})).not.toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(onSave).not.toHaveBeenCalled()
  })
})

function render(component: JSX.Element, {models, ...opts}: TestRenderOptions & {models?: RepoModel[]} = {}) {
  return htmlRender(<ModelsProvider models={models ?? []}>{component}</ModelsProvider>, opts)
}
