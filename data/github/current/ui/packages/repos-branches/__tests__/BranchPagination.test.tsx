import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import BranchPagination from '../components/BranchPagination'
import {getListRoutePayload} from '../test-utils/mock-data'

test('renders BranchPagination as null when a single page of data given', () => {
  const routePayload = getListRoutePayload()
  render(<BranchPagination />, {
    routePayload,
  })

  expect(screen.queryByRole('navigation', {name: 'Pagination'})).toBeNull()
})

test('renders BranchPagination when there are multiple pages of data', () => {
  const routePayload = getListRoutePayload()
  render(<BranchPagination />, {
    routePayload: {
      ...routePayload,
      has_more: true,
    },
  })

  expect(screen.getByRole('navigation', {name: 'Pagination'})).toBeVisible()
})

test('renders BranchPagination with a next link and disabled previous button', async () => {
  const routePayload = getListRoutePayload()
  render(<BranchPagination />, {
    routePayload: {
      ...routePayload,
      current_page: 1,
      has_more: true,
    },
  })

  const paginationArea = await screen.findByRole('navigation', {name: 'Pagination'})
  expect(paginationArea).toBeInTheDocument()
  const previous = within(paginationArea).getByText('Previous')
  expect(previous.attributes.getNamedItem('aria-hidden')).toBeTruthy()
  const next = screen.getByRole('link', {name: 'Next Page'})
  expect(next.attributes.getNamedItem('aria-hidden')).toBeFalsy()
})

test('renders BranchPagination with a next link and previous link', () => {
  const routePayload = getListRoutePayload()
  render(<BranchPagination />, {
    routePayload: {
      ...routePayload,
      current_page: 2,
      has_more: true,
    },
  })

  const previous = screen.getByRole('link', {name: 'Previous Page'})
  expect(previous.attributes.getNamedItem('aria-disabled')).toBeFalsy()
  const next = screen.getByRole('link', {name: 'Next Page'})
  expect(next.attributes.getNamedItem('aria-disabled')).toBeFalsy()
})

test('renders BranchPagination with a disabled next button and previous link', async () => {
  const routePayload = getListRoutePayload()
  render(<BranchPagination />, {
    routePayload: {
      ...routePayload,
      current_page: 2,
      has_more: false,
    },
  })

  const previous = screen.getByRole('link', {name: 'Previous Page'})
  expect(previous.attributes.getNamedItem('aria-hidden')).toBeFalsy()

  const paginationArea = await screen.findByRole('navigation', {name: 'Pagination'})
  expect(paginationArea).toBeInTheDocument()
  expect(screen.getByText('Next').attributes.getNamedItem('aria-hidden')).toBeTruthy()
})
