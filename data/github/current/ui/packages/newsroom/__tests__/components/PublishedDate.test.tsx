import {render, screen} from '@testing-library/react'
import {PublishedDate, type PublishedDateProps} from '../../components/PublishedDate/PublishedDate'

describe('PublishedDate', () => {
  const publishedDateOnly: PublishedDateProps = {
    publishedDate: '2024-08-20',
  }

  const allProps: PublishedDateProps = {
    publishedDate: '2024-08-20',
    updatedDate: '2024-08-27',
  }

  const invalidPublishedDate = {
    publishedDate: 'invalid-date',
  }

  const invalidUpdatedDate = {
    publishedDate: '2024-08-20',
    updatdDate: 'invalid-date',
  }

  const samePublishedAndUpdatedDate = {
    publishedDate: '2024-08-20',
    updatedDate: '2024-08-20',
  }

  it('renders the published date', () => {
    render(<PublishedDate {...publishedDateOnly} />)
    expect(screen.getByText('August 20, 2024')).toBeInTheDocument()
  })

  it('renders the updated date', () => {
    render(<PublishedDate {...allProps} />)

    // separate expects as dates are rendered in separate <time> elements
    expect(screen.getByText('August 20, 2024')).toBeInTheDocument()
    expect(screen.getByText('• updated')).toBeInTheDocument()
    expect(screen.getByText('August 27, 2024')).toBeInTheDocument()
  })

  it('does not render if the published date is invalid', () => {
    render(<PublishedDate {...invalidPublishedDate} />)
    expect(screen.queryByText('August 20, 2024')).not.toBeInTheDocument()
  })

  it('only renders the published date if the updated date is invalid', () => {
    render(<PublishedDate {...invalidUpdatedDate} />)
    expect(screen.getByText('August 20, 2024')).toBeInTheDocument()
    expect(screen.queryByText('August 27, 2024')).not.toBeInTheDocument()
  })

  it('only renders the published date if the updated date is the same as the published date', () => {
    render(<PublishedDate {...samePublishedAndUpdatedDate} />)
    expect(screen.getByText('August 20, 2024')).toBeInTheDocument()
    expect(screen.queryByText('updated')).not.toBeInTheDocument()
  })
})
