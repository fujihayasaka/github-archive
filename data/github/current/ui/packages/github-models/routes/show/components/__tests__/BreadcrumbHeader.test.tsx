import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {BreadcrumbHeader} from '../BreadcrumbHeader'
import {mockModel} from '../../../playground/__tests__/mocks'

describe('BreadcrumbHeader', () => {
  test('renders', () => {
    const model = Object.assign({}, mockModel, {publisher: 'AI21Labs'})

    render(<BreadcrumbHeader model={model} />)

    expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Marketplace'})).toHaveAttribute('href', '/marketplace')
    expect(screen.getByRole('link', {name: 'Models'})).toHaveAttribute('href', '/marketplace/models/catalog')
    expect(screen.getByText('AI21 Labs')).toBeInTheDocument()
  })
})
