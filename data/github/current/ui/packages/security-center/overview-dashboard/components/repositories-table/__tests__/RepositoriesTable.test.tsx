import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import {RepositoriesTable} from '../RepositoriesTable'
import useRepositoriesQuery from '../use-repositories-query'

afterEach(() => {
  jest.clearAllMocks()
})

jest.mock('../use-repositories-query')
function mockUseRepositoriesQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useRepositoriesQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSucess: true,
    data: {},
    ...result,
  })
}

describe('RepositoriesTable', () => {
  const query = 'archived:false'
  const startDate = '2022-01-01'
  const endDate = '2023-01-31'

  it('renders the component with the correct props', () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        repositories: [
          {
            id: 1,
            repository: 'my-repo',
            ownerType: 'ORGANIZATION',
            total: 1337,
            critical: 7331,
            high: 3173,
            medium: 3371,
            low: 1733,
            url: 'http://foo',
          },
        ],
      },
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(screen.getByText('Repository')).toBeInTheDocument()
    expect(screen.getByText('Open alerts')).toBeInTheDocument()
    expect(screen.getByText('Critical')).toBeInTheDocument()
    expect(screen.getByText('High')).toBeInTheDocument()
    expect(screen.getByText('Medium')).toBeInTheDocument()
    expect(screen.getByText('Low')).toBeInTheDocument()
  })

  it('fetches and displays the correct data', async () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        repositories: [
          {
            id: 1,
            repository: 'my-repo',
            ownerType: 'ORGANIZATION',
            total: 1337,
            critical: 7331,
            high: 3173,
            medium: 3371,
            low: 1733,
            url: 'http://foo',
          },
        ],
      },
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(screen.getByText('my-repo')).toBeInTheDocument()
    expect(screen.getByText('my-repo')).toHaveAttribute('href', 'http://foo')
    expect(screen.getByText('1,337')).toBeInTheDocument()
    expect(screen.getByText('7,331')).toBeInTheDocument()
    expect(screen.getByText('3,173')).toBeInTheDocument()
    expect(screen.getByText('3,371')).toBeInTheDocument()
    expect(screen.getByText('1,733')).toBeInTheDocument()
  })

  it('fetches and displays the correct data for user-owned repository', async () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        repositories: [
          {
            id: 1,
            repository: 'my-repo',
            ownerType: 'USER',
            url: '/orgs/my-org/security/alerts/secret-scanning?query=repo%3Amy-repo',
          },
        ],
      },
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(screen.getByText('my-repo')).toBeInTheDocument()
    expect(screen.getByText('my-repo')).toHaveAttribute(
      'href',
      '/orgs/my-org/security/alerts/secret-scanning?query=repo%3Amy-repo',
    )
  })

  it('displays N/A for null counts', async () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        repositories: [
          {
            id: 1,
            repository: 'my-repo',
            ownerType: 'ORGANIZATION',
            total: 1337,
            critical: 7331,
            high: null,
            medium: 3371,
            low: 1733,
            url: 'http://foo',
          },
        ],
      },
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(screen.getByText('my-repo')).toBeInTheDocument()
    expect(screen.getByText('my-repo')).toHaveAttribute('href', 'http://foo')
    expect(screen.getByText('1,337')).toBeInTheDocument()
    expect(screen.getByText('7,331')).toBeInTheDocument()
    expect(screen.getByText('N/A')).toBeInTheDocument()
    expect(screen.getByText('3,371')).toBeInTheDocument()
    expect(screen.getByText('1,733')).toBeInTheDocument()
  })

  it('displays an error state on error', async () => {
    mockUseRepositoriesQuery({
      isSuccess: false,
      isError: true,
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(await screen.findByTestId('error')).toBeInTheDocument()
  })

  it('displays an empty state on no data', async () => {
    mockUseRepositoriesQuery({
      isSuccess: true,
      data: {
        repositories: [],
      },
    })

    render(<RepositoriesTable query={query} startDate={startDate} endDate={endDate} />)

    expect(await screen.findByTestId('empty')).toBeInTheDocument()
  })
})
