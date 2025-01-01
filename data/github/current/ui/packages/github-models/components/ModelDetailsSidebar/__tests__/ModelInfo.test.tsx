import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {modelPath} from '@github-ui/paths'
import ModelInfo from '../ModelInfo'
import {mockModel} from '../../../routes/playground/__tests__/mocks'

describe('ModelInfo', () => {
  test('renders as button', () => {
    const expectedUrl = modelPath(mockModel)

    const {container} = render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="button" />)

    const sidebarInfoEl = within(container).getByTestId('sidebar-info')
    expect(sidebarInfoEl).toBeInTheDocument()
    expect(within(sidebarInfoEl).getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Model details page'})).toHaveAttribute('href', expectedUrl)
  })

  test('renders as action list item', () => {
    const expectedUrl = modelPath(mockModel)

    const {container} = render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="listitem" />)

    const sidebarInfoEl = within(container).getByTestId('sidebar-info')
    expect(sidebarInfoEl).toBeInTheDocument()
    expect(within(sidebarInfoEl).getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Model details page'})).toHaveAttribute('href', expectedUrl)
  })
})
