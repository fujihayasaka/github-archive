import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockModels} from '../../../../test-utils/mock-data'
import type {RepoModel} from '../../../../types'
import {ModelsProvider} from '../../contexts/ModelsContext'
import ModelPicker from '../ModelPicker'

const onSelect = jest.fn().mockName('onSelect')

describe('ModelPicker', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders when no model is selected and none are available', async () => {
    const {user} = render(<ModelPicker onSelect={onSelect} />, [])

    const button = screen.getByRole('button', {name: 'Select model'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-variant', 'default')

    await user.click(button)

    expect(screen.getByRole('heading', {name: 'No models available'})).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select model'})).not.toBeInTheDocument()
    expect(onSelect).not.toHaveBeenCalled()
  })

  it('renders when no model is selected but one is available', async () => {
    const {user} = render(<ModelPicker onSelect={onSelect} />, mockModels)

    const button = screen.getByRole('button', {name: 'Select model'})
    expect(button).toBeInTheDocument()

    await user.click(button)

    const dialog = screen.getByRole('dialog', {name: 'Select model'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Select model'})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'Filter models'})).toBeInTheDocument()
    const listbox = within(dialog).getByRole('listbox', {name: 'Select model'})
    expect(listbox).toBeInTheDocument()
    for (const model of mockModels) {
      expect(within(listbox).getByRole('option', {name: model.friendly_name})).toBeInTheDocument()
    }
    expect(onSelect).not.toHaveBeenCalled()

    await user.click(within(listbox).getByRole('option', {name: mockModels[0]!.friendly_name}))

    expect(onSelect).toHaveBeenCalledTimes(1)
    expect(onSelect).toHaveBeenCalledWith(mockModels[0])
  })

  it('renders when a model is selected', async () => {
    const selectedModel = mockModels[0]!
    const {user} = render(<ModelPicker onSelect={onSelect} selectedModel={selectedModel} />, mockModels)

    expect(screen.queryByRole('button', {name: 'Select model'})).not.toBeInTheDocument()
    expect(screen.getByRole('img', {name: `${selectedModel.publisher} logo`})).toBeInTheDocument()
    const button = screen.getByRole('button', {name: `${selectedModel.publisher} logo ${selectedModel.friendly_name}`})
    expect(button).toBeInTheDocument()

    await user.click(button)

    const dialog = screen.getByRole('dialog', {name: selectedModel.friendly_name})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: selectedModel.friendly_name})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'Filter models'})).toBeInTheDocument()
    const listbox = within(dialog).getByRole('listbox', {name: selectedModel.friendly_name})
    expect(listbox).toBeInTheDocument()
    const selectedModelOption = within(listbox).getByRole('option', {name: selectedModel.friendly_name})
    expect(selectedModelOption).toBeInTheDocument()
    expect(selectedModelOption).toHaveAttribute('aria-selected', 'true')
    expect(onSelect).not.toHaveBeenCalled()
  })

  it('renders button with custom styling', () => {
    render(<ModelPicker buttonProps={{className: 'foo', variant: 'invisible'}} onSelect={onSelect} />, mockModels)

    const button = screen.getByRole('button', {name: 'Select model'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveClass('foo')
    expect(button).toHaveAttribute('data-variant', 'invisible')
  })
})

function render(component: JSX.Element, models: RepoModel[]) {
  return htmlRender(<ModelsProvider models={models}>{component}</ModelsProvider>)
}
