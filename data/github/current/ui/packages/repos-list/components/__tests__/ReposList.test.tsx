import {mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {NoReposMessage} from '@github-ui/repos-list-shared'
import {screen} from '@testing-library/react'

import {getRepositoriesRoutePayload} from '../../test-utils/mock-data'
import {ReposList} from '../ReposList'

const defaultProps = {
  compactMode: false,
  showSpinner: false,
  repositoryCount: 3,
  repos: [],
  onSortingItemSelect: jest.fn(),
  noReposMessage: <NoReposMessage currentPage={1} pageCount={1} />,
}

describe('ReposList', () => {
  test('renders the ReposList', () => {
    render(<ReposList {...defaultProps} />)

    expect(screen.getByRole('heading', {name: 'Repositories list'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: '3 repositories'})).toBeInTheDocument()
    // Density toggle is hidden in narrow screens,
    // but we can still check and click the buttons using `hidden: true`
    expect(screen.getByRole('button', {name: 'Comfortable display density', hidden: true})).toHaveAttribute(
      'aria-current',
      'true',
    )
    expect(screen.getByRole('button', {name: 'Compact display density', hidden: true})).toHaveAttribute(
      'aria-current',
      'false',
    )
  })

  test('updates compact mode preferences', async () => {
    const preferencesFetch = mockFetch.mockRoute('/repos/preferences', {notice: 'Saved'})

    const {user} = render(<ReposList {...defaultProps} compactMode />)

    const comfortableButton = screen.getByRole('button', {name: 'Comfortable display density', hidden: true})
    expect(comfortableButton).toHaveAttribute('aria-current', 'false')
    const compactButton = screen.getByRole('button', {name: 'Compact display density', hidden: true})
    expect(compactButton).toHaveAttribute('aria-current', 'true')
    expect(preferencesFetch).not.toHaveBeenCalled()

    await user.click(comfortableButton)

    expect(comfortableButton).toHaveAttribute('aria-current', 'true')
    expect(compactButton).toHaveAttribute('aria-current', 'false')
    expect(preferencesFetch).toHaveBeenCalledTimes(1)

    await user.click(compactButton)

    expect(comfortableButton).toHaveAttribute('aria-current', 'false')
    expect(compactButton).toHaveAttribute('aria-current', 'true')
    expect(preferencesFetch).toHaveBeenCalledTimes(2)
  })

  it('renders header with no repos', () => {
    render(<ReposList {...defaultProps} repositoryCount={0} />)
    expect(screen.getByText('0 repositories')).toBeInTheDocument()
  })

  it('renders header and all expected elements', () => {
    render(<ReposList {...defaultProps} repositoryCount={5000} repos={getRepositoriesRoutePayload().repositories} />)

    expect(screen.getByText('5k repositories')).toBeInTheDocument()
    expect(screen.getByText('test-repo')).toBeInTheDocument()
    expect(screen.getByTestId('trains-topic-link')).toBeInTheDocument()
  })

  it('renders compact rows initially if remembered so', () => {
    render(
      <ReposList
        {...defaultProps}
        compactMode
        repositoryCount={5000}
        repos={getRepositoriesRoutePayload().repositories}
      />,
    )

    expect(screen.getByText('5k repositories')).toBeInTheDocument()
    expect(screen.getByText('test-repo')).toBeInTheDocument()
  })
})
