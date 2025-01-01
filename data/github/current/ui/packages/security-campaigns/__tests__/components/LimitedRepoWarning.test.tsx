import {render, screen} from '@testing-library/react'
import {LimitedRepoWarning} from '../../components/LimitedRepoWarning'

describe('LimitedRepoWarning', () => {
  const defaultProps = {
    href: '/example-link',
  }

  it('renders warning message when show is true', () => {
    render(<LimitedRepoWarning {...defaultProps} />)

    const warning = screen.getByTestId('incomplete-data-warning')
    expect(warning).toBeInTheDocument()
    expect(warning).toHaveTextContent('Results are based on a limited selection of repositories.')
    expect(screen.getByRole('link')).toHaveAttribute('href', '/example-link')
  })
})
