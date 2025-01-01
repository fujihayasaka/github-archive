import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockModels, mockPromptConfig} from '../../../../test-utils/mock-data'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {promptModelIdentifierFor} from '../../models'
import {InlinePrompt} from '../InlinePrompt'

describe('InlinePrompt', () => {
  it('renders when model selection cannot be changed', () => {
    const model = mockModels[0]!
    const prompt = mockPromptConfig({model: promptModelIdentifierFor(model)})

    render(<InlinePrompt prompt={prompt} promptIndex={0} />)

    expect(screen.getByRole('img', {name: `${model.publisher} logo`})).toBeInTheDocument()
    expect(screen.getByText(model.friendly_name)).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: model.friendly_name})).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', {name: `${model.publisher} logo ${model.friendly_name}`}),
    ).not.toBeInTheDocument()
  })

  it('renders when model selection can be changed', async () => {
    const model = mockModels[0]!
    const prompt = mockPromptConfig({model: promptModelIdentifierFor(model)})
    const onModelSelect = jest.fn().mockName('onModelSelect')

    const {user} = render(<InlinePrompt prompt={prompt} promptIndex={0} onModelSelect={onModelSelect} />)

    expect(onModelSelect).not.toHaveBeenCalled()
    expect(screen.getByRole('img', {name: `${model.publisher} logo`})).toBeInTheDocument()
    const modelPickerToggle = screen.getByRole('button', {name: `${model.publisher} logo ${model.friendly_name}`})
    expect(modelPickerToggle).toBeInTheDocument()
    expect(modelPickerToggle).toBeEnabled()
    expect(screen.queryByRole('dialog', {name: model.friendly_name})).not.toBeInTheDocument()

    await user.click(modelPickerToggle)

    const modelPickerDialog = screen.getByRole('dialog', {name: model.friendly_name})
    expect(modelPickerDialog).toBeInTheDocument()
    expect(within(modelPickerDialog).getByRole('heading', {name: model.friendly_name})).toBeInTheDocument()
    expect(within(modelPickerDialog).getByRole('textbox', {name: 'Filter models'})).toBeInTheDocument()
    const modelList = within(modelPickerDialog).getByRole('listbox', {name: model.friendly_name})
    expect(modelList).toBeInTheDocument()
    for (const otherModel of mockModels) {
      expect(within(modelList).getByRole('option', {name: otherModel.friendly_name})).toBeInTheDocument()
    }
    const otherModel = mockModels[1]!

    await user.click(within(modelList).getByRole('option', {name: otherModel.friendly_name}))

    expect(onModelSelect).toHaveBeenCalledWith(otherModel, 0)
    expect(onModelSelect).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('dialog', {name: model.friendly_name})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element) {
  return htmlRender(<ModelsProvider models={mockModels}>{component}</ModelsProvider>)
}
