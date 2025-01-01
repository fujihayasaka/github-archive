import {describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {screen} from '@testing-library/react'

import {render} from '../../test-utils/helpers'
import {getProviders} from '../../test-utils/mocks'
import {ProviderPicker} from '../ProviderPicker'

describe('ProviderPicker', () => {
  it('renders the providers', async () => {
    render(<ProviderPicker providers={getProviders()} />)

    await userEvent.click(screen.getByRole('button', {name: 'Select provider'}))
    expect(screen.getByRole('option', {name: 'OpenAI'})).toBeInTheDocument()
  })

  it('when selected is passed, we render it', () => {
    const providers = getProviders()
    render(<ProviderPicker providers={providers} selected={providers.at(1)} />)
    expect(screen.getByRole('button', {name: 'Azure AI'})).toBeInTheDocument()
  })

  it('renders a filtered list when searching', async () => {
    const providers = getProviders()
    render(<ProviderPicker providers={providers} />)

    await userEvent.click(screen.getByRole('button', {name: 'Select provider'}))

    const searchField = screen.getByLabelText('Filter providers')
    await userEvent.fill(searchField, 'AI')

    expect(screen.getAllByRole('option', {name: /\w+/})).toHaveLength(2)

    await userEvent.fill(searchField, 'Azure')

    expect(screen.getAllByRole('option', {name: /\w+/})).toHaveLength(1)
    expect(screen.getByRole('option', {name: 'Azure AI'})).toBeInTheDocument()
  })

  it('can select an item', async () => {
    const intendedSelectedProvider = getProviders()[1]
    const providers = getProviders()
    const onSelect = vi.fn()
    render(<ProviderPicker providers={providers} onSelected={onSelect} />)

    await userEvent.click(screen.getByRole('button', {name: 'Select provider'}))
    await userEvent.click(screen.getByRole('option', {name: 'Azure AI'}))

    expect(onSelect).toHaveBeenCalledExactlyOnceWith(intendedSelectedProvider)
  })

  it('does not select anything when the user cancels', async () => {
    const providers = getProviders()
    const onSelect = vi.fn()
    render(<ProviderPicker providers={providers} onSelected={onSelect} />)

    const panelButton = screen.getByRole('button', {name: 'Select provider'})
    await userEvent.click(panelButton)

    expect(panelButton.getAttribute('aria-expanded')).toBe('true')

    await userEvent.keyboard('{Escape}')

    expect(panelButton.getAttribute('aria-expanded')).toBe('false')

    expect(onSelect).toBeCalledTimes(0)
  })

  it('cannot be interacted with when disabled', async () => {
    const providers = getProviders()
    const onSelect = vi.fn()
    render(<ProviderPicker providers={providers} onSelected={onSelect} disabled />)

    const panelButton = screen.getByRole('button', {name: 'Select provider'})
    expect(panelButton).toBeDisabled()

    await expect(userEvent.click(panelButton, {timeout: 100})).rejects.toThrow(
      /waiting for element to be visible, enabled and stable/,
    )

    expect(panelButton.getAttribute('aria-expanded')).not.toBe('true')
    expect(screen.queryByRole('option')).not.toBeInTheDocument()
    expect(onSelect).not.toHaveBeenCalled()
  })
})
