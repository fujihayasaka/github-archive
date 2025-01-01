import {noop} from '@github-ui/noop'
import {describe, expect, it} from '@github-ui/tests'
import {screen} from '@testing-library/react'

import {render} from '../../test-utils/helpers'
import {mockSelectorModel} from '../../test-utils/mocks'
import {ModelSelectorPane} from '../ModelSelectorPane'

describe('ModelSelectorPane', () => {
  it('renders the blankslate when there are no models', () => {
    render(<ModelSelectorPane models={[]} selected={[]} />)
    expect(screen.getByText(/Add a valid key/)).toBeInTheDocument()
  })

  it('renders a loading state', () => {
    render(<ModelSelectorPane models={[]} selected={[]} loading />)
    expect(screen.queryByText(/Add a valid key/)).not.toBeInTheDocument()
    expect(screen.getByText(/Loading.../)).toBeInTheDocument()
  })

  it('renders the models', () => {
    const model = mockSelectorModel()
    render(<ModelSelectorPane models={[model]} selected={[]} onSelect={noop} />)
    expect(screen.getByRole('checkbox', {name: model.name})).toBeInTheDocument()
  })

  it('selected models are checked', () => {
    const model = mockSelectorModel()
    render(<ModelSelectorPane models={[model]} selected={[model.slug]} onSelect={noop} />)
    expect(screen.getByRole('checkbox', {name: model.name})).toBeChecked()
  })

  it('interactions are disabled when disabled', () => {
    const model = mockSelectorModel()
    render(<ModelSelectorPane models={[model]} selected={[]} onSelect={noop} disabled />)
    const checkbox = screen.getByRole('checkbox', {name: model.name})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).toBeDisabled()
    expect(screen.queryByRole('button', {name: 'Edit'})).not.toBeInTheDocument()
  })
})
