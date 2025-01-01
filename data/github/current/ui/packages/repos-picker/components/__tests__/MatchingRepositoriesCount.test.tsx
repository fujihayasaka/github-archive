// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {MatchingRepositoriesCount} from '../MatchingRepositoriesCount'

describe('MatchingRepositoriesCount', () => {
  it('displays nothing when loading', () => {
    render(<MatchingRepositoriesCount query="test" scope={{type: 'organization', slug: 'github'}} />)

    expect(document.body).toHaveTextContent('')
  })

  it('displays the correct message when there are matching repositories', async () => {
    mockFetch.mockRouteOnce(/\/repositories\/picker\/count/, {totalCount: 5})

    render(<MatchingRepositoriesCount query="test" scope={{type: 'organization', slug: 'github'}} />)

    expect(await screen.findByText('Matching 5 repositories')).toBeInTheDocument()
  })

  it('renders count as link if href is provided', async () => {
    mockFetch.mockRouteOnce(/\/repositories\/picker\/count/, {totalCount: 5})
    render(<MatchingRepositoriesCount query="test" scope={{type: 'organization', slug: 'github'}} href="github.com" />)

    expect(await screen.findByRole('link')).toHaveTextContent('Matching 5 repositories')
  })

  it('displays nothing when the query is empty, request is skipped', async () => {
    render(<MatchingRepositoriesCount scope={{type: 'organization', slug: 'github'}} />)

    expectMockFetchCalledTimes(/\/repositories\/picker\/count/, 0)

    expect(document.body).toHaveTextContent('')
  })
})
