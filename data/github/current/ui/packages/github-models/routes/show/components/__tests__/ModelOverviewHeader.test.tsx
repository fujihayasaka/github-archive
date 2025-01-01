import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ModelOverviewHeader} from '../ModelOverviewHeader'
import {mockGettingStarted, mockModel} from '../../../playground/__tests__/mocks'

describe('ModelOverviewHeader', () => {
  test('renders when user can use the model', () => {
    const model = Object.assign({}, mockModel, {
      friendly_name: 'FooBar',
      registry: 'foo',
      name: 'bar',
      publisher: 'Open AI',
    })

    render(<ModelOverviewHeader model={model} gettingStarted={mockGettingStarted} canUseModel />)

    expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Give feedback'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Playground'})).toHaveAttribute(
      'href',
      '/marketplace/models/foo/bar/playground',
    )
    expect(screen.getByRole('img', {name: 'Open AI logo'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'FooBar', level: 1})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Use this model'})).toBeInTheDocument()
  })

  test('renders when user cannot use the model', () => {
    const model = Object.assign({}, mockModel, {
      friendly_name: 'FooBar',
      registry: 'foo',
      name: 'bar',
      publisher: 'Open AI',
    })

    render(<ModelOverviewHeader model={model} gettingStarted={mockGettingStarted} canUseModel={false} />)

    expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Give feedback'})).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Playground'})).not.toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'Open AI logo'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'FooBar', level: 1})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Use this model'})).toBeInTheDocument()
  })
})
