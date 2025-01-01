import {noop} from '@github-ui/noop'
import {describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {screen, waitFor} from '@testing-library/react'

import {render} from '../../test-utils/helpers'
import {mockSelectorModel} from '../../test-utils/mocks'
import {ModelSelectorConfig} from '../ModelSelectorConfig'

describe('ModelSelectorConfig', () => {
  it('renders', () => {
    const model = mockSelectorModel()
    render(<ModelSelectorConfig model={model} onSelect={noop} selected />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toHaveAttribute('aria-checked', 'true')
  })

  it('when the model has a custom name, its labeled as such', () => {
    const model = mockSelectorModel({name: 'Custom Model Name'})
    render(<ModelSelectorConfig model={model} onSelect={noop} selected />)
    const checkbox = screen.getByRole('checkbox', {name: model.name})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByText(model.slug), 'The models real name should still be visible').toBeInTheDocument()
  })

  it('calls select handler when checkbox is clicked', async () => {
    const model = mockSelectorModel()
    const onSelect = vi.fn()
    render(<ModelSelectorConfig model={model} onSelect={onSelect} />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toHaveAttribute('aria-checked', 'false')
    await userEvent.click(checkbox)
    expect(onSelect).toHaveBeenCalledWith(true, model)
    // Note; because `ModelSelectorConfig` is a controlled input, the checkbox will not be checked
    // after the interaction, unless the `onSelect` handler updates the selected prop.
    expect(checkbox).toHaveAttribute('aria-checked', 'false')
  })

  it('pressing space on the checkbox toggles the checkbox', async () => {
    const model = mockSelectorModel()
    const onSelect = vi.fn()
    render(<ModelSelectorConfig model={model} onSelect={onSelect} />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toHaveAttribute('aria-checked', 'false')

    await userEvent.type(checkbox, ' ')
    expect(onSelect).toHaveBeenCalledWith(true, model)

    // Note; because `ModelSelectorConfig` is a controlled input, the checkbox will not be checked
    // after the interaction, unless the `onSelect` handler updates the selected prop.
    expect(checkbox).toHaveAttribute('aria-checked', 'false')
  })

  it('pressing space unless on the checkbox behaves naturally', async () => {
    const model = mockSelectorModel()
    const onSelect = vi.fn()
    render(<ModelSelectorConfig model={model} onSelect={onSelect} editable />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toHaveAttribute('aria-checked', 'false')

    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    const input = screen.getByLabelText('Edit value')
    await waitFor(() => expect(input).toHaveFocus())
    await userEvent.keyboard(' ')
    await waitFor(() => expect(input).toHaveFocus()) // The input should still be active
    expect(input).toHaveValue(' ')
  })

  it('when a model is deprecated, is not selectable but can still edit', async () => {
    const model = mockSelectorModel({deprecated: true})
    const onSelect = vi.fn()
    render(<ModelSelectorConfig model={model} onSelect={onSelect} editable />)
    const checkbox = screen.getByRole('checkbox', {name: `Deprecated model ${model.slug}`})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toBeDisabled()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeInTheDocument()
    // We force, because technically disabled elements are not interactable.
    await userEvent.click(checkbox, {force: true})
    expect(onSelect).not.toHaveBeenCalled()
  })

  it('when a model is new it can not also be deprecated', () => {
    const model = mockSelectorModel({fresh: true, deprecated: true})
    render(<ModelSelectorConfig model={model} onSelect={noop} editable />)
    const checkbox = screen.getByRole('checkbox', {name: `Deprecated model ${model.slug}`})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toBeDisabled()

    expect(screen.queryByText('New')).not.toBeInTheDocument()
  })

  it('correct tab cycle behavior when editable', async () => {
    const model = mockSelectorModel()
    render(<ModelSelectorConfig model={model} onSelect={noop} editable />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    await userEvent.tab()
    await waitFor(() => expect(checkbox).toHaveFocus())
    await userEvent.tab()
    await waitFor(() => expect(screen.getByRole('button', {name: 'Edit'})).toHaveFocus())
  })

  it('interactions are disabled when disabled', () => {
    const model = mockSelectorModel()
    render(<ModelSelectorConfig model={model} onSelect={noop} editable disabled />)
    const checkbox = screen.getByRole('checkbox', {name: model.slug})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toBeDisabled()
    expect(screen.queryByRole('button', {name: 'Edit'})).not.toBeInTheDocument()
  })
})
