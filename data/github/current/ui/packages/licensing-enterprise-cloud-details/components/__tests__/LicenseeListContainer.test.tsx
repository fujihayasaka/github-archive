import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {LicenseeListContainer} from '../LicenseeListContainer'
import {useQuery} from '@github-ui/react-query'
import {useNavigation as mockUseNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {VisualStudioFilter} from '../../types/visual-studio-filter-options'

beforeEach(() => {
  ;(mockUseNavigation as jest.Mock).mockReturnValue({
    basePath: '/test-base-path',
    enterpriseContactUrl: '/enterprise-contact-url',
    isStafftools: false,
    isTeams: false,
    slug: 'test-co',
  })
})

jest.mock('@github-ui/licensing-common/contexts/NavigationContext', () => {
  const actual = jest.requireActual('@github-ui/licensing-common/contexts/NavigationContext')
  return {
    ...actual,
    useNavigation: jest.fn(),
  }
})

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))
jest.mock('@github-ui/react-query', () => ({
  useQuery: jest.fn(),
}))
// make debounce a no-op so it doesn't schedule timers in Jest
jest.mock('@github-ui/use-debounce', () => ({
  useDebounce: (cb: (...args: unknown[]) => void) => cb, // no delay
}))

const mockLicensees = [
  {
    id: 1,
    login: 'Alice',
    fullName: 'Alice Johnson',
    avatarUrl: '',
    accessType: 'Admin',
    license: 'GitHub',
  },
  {
    id: 2,
    login: 'Bob',
    fullName: 'Bob Smith',
    avatarUrl: '',
    accessType: 'User',
    license: 'GitHub',
  },
]

const renderLicenseeListContainer = () => render(<LicenseeListContainer isVolumeLicensed={false} />)

describe('LicenseeListContainer Component', () => {
  it('renders fetched licensees', async () => {
    ;(useQuery as jest.Mock).mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: mockLicensees,
        totalPages: 1,
      },
    })

    renderLicenseeListContainer()

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument()
    })

    expect(screen.getByText('Alice Johnson')).toBeInTheDocument()
    expect(screen.getByText('Admin')).toBeInTheDocument()
    expect(screen.getByText('Bob')).toBeInTheDocument()
    expect(screen.getByText('Bob Smith')).toBeInTheDocument()
    expect(screen.getByText('User')).toBeInTheDocument()
  })

  it('renders loading state', () => {
    ;(useQuery as jest.Mock).mockReturnValue({
      isFetching: true,
      isError: false,
      data: {
        licensees: [],
        totalPages: 1,
      },
    })

    renderLicenseeListContainer()

    // Table.Skeleton will render rows but won't have content — so just check it's in the DOM
    expect(screen.getByRole('table')).toBeInTheDocument()
  })

  it('renders error state', async () => {
    ;(useQuery as jest.Mock).mockReturnValue({
      isFetching: false,
      isError: true,
      data: undefined,
    })

    renderLicenseeListContainer()

    await waitFor(() => {
      expect(screen.getByText('Licensed users cannot be loaded')).toBeInTheDocument()
    })
    expect(screen.getByText('contact support')).toBeInTheDocument()
  })

  it('renders empty state', async () => {
    ;(useQuery as jest.Mock).mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: [],
        totalPages: 1,
      },
    })

    renderLicenseeListContainer()

    await waitFor(() => {
      expect(screen.getByText('No licensed users')).toBeInTheDocument()
    })
  })

  it('handles search input', async () => {
    const useQueryMock = useQuery as jest.Mock
    // Initial render
    useQueryMock.mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: mockLicensees,
        totalPages: 1,
      },
    })

    const {user} = renderLicenseeListContainer()

    const searchInput = screen.getByLabelText('Search users')

    // Update search query
    await user.type(searchInput, 'Alice')

    // Verify that search query was updated and useQuery was called with updated parameters
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      expect(queryKey).toContain('Alice')
    })
  })

  it('resets to page 1 when search query changes', async () => {
    const useQueryMock = useQuery as jest.Mock

    // Initial render with multiple pages
    useQueryMock.mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: mockLicensees,
        totalPages: 3,
      },
    })

    const {user} = renderLicenseeListContainer()

    // Navigate to page 2
    const page2Button = screen.getByText('2')
    await user.click(page2Button)

    // Verify page 2 is active
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      expect(queryKey.includes(2)).toBeTruthy() // Current page should be 2
    })

    // Now search for something
    const searchInput = screen.getByLabelText('Search users')
    await user.type(searchInput, 'test query')

    // Verify that page was reset to 1
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      // Page should be reset to 1
      expect(queryKey.includes(1)).toBeTruthy()
    })

    // Verify that search query was included
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      expect(queryKey.includes('test query')).toBeTruthy()
    })
  })

  it('handles Visual Studio filter changes', async () => {
    const useQueryMock = useQuery as jest.Mock

    // Initial render
    useQueryMock.mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: mockLicensees,
        totalPages: 1,
      },
    })

    const {user} = renderLicenseeListContainer()

    // Open the filter menu
    const filterButton = screen.getByText(/Visual Studio:/i)
    await user.click(filterButton)

    // Select "Unmatched" filter option
    const unmatchedOption = screen.getByText('Unmatched')
    await user.click(unmatchedOption)

    // Verify filter was applied
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      expect(queryKey.includes(VisualStudioFilter.Unmatched)).toBeTruthy()
    })
  })

  it('handles pagination', async () => {
    const useQueryMock = useQuery as jest.Mock

    // Initial render with multiple pages
    useQueryMock.mockReturnValue({
      isFetching: false,
      isError: false,
      data: {
        licensees: mockLicensees,
        totalPages: 3,
      },
    })

    const {user} = renderLicenseeListContainer()

    // Navigate to page 3
    const page3Button = screen.getByText('3')
    await user.click(page3Button)

    // Verify page 3 was requested
    await waitFor(() => {
      const lastCall = useQueryMock.mock.calls[useQueryMock.mock.calls.length - 1]
      const queryKey = lastCall[0].queryKey
      expect(queryKey.includes(3)).toBeTruthy() // Current page should be 3
    })
  })
})
