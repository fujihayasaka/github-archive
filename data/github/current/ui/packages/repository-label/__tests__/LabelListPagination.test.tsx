import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {LabelListPagination} from '../LabelListPagination'

describe('LabelListPagination', () => {
  it('renders pagination with correct number of pages', () => {
    render(<LabelListPagination dataCount={50} />)
    expect(screen.getByRole('link', {name: 'Page 1'})).toBeInTheDocument()
    const pageTwo = screen.getByRole('link', {name: 'Page 2'})
    expect(pageTwo).toBeInTheDocument()
    expect(pageTwo).toHaveAttribute('href', '/?page=2')
    expect(screen.getByRole('link', {name: 'Next Page'})).toBeInTheDocument()
  })

  it('navigates to the next page when Next is clicked', async () => {
    const {user} = render(<LabelListPagination dataCount={50} />)

    await user.click(screen.getByRole('link', {name: 'Next Page'}))
    expect(screen.getByRole('link', {name: 'Page 2'})).toHaveAttribute('aria-current', 'page')
  })

  it('navigates to the previous page when Previous is clicked', async () => {
    const {user} = render(<LabelListPagination dataCount={50} />)

    await user.click(screen.getByRole('link', {name: 'Next Page'}))
    await user.click(screen.getByRole('link', {name: 'Previous Page'}))
    expect(screen.getByRole('link', {name: 'Page 1'})).toHaveAttribute('aria-current', 'page')
  })

  it('disables Previous button on the first page', () => {
    render(<LabelListPagination dataCount={50} />)
    expect(screen.getByText('Previous')).toHaveAttribute('aria-disabled', 'true')
  })

  it('disables Next button on the last page', () => {
    render(<LabelListPagination dataCount={10} />)
    expect(screen.getByText('Next')).toHaveAttribute('aria-disabled', 'true')
  })
})
