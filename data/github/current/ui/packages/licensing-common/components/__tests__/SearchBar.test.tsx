import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getSearchBarProps} from '../../../licensing-common/test-utils/mock-data'
import {SearchBar} from '../SearchBar'

const renderSearchBar = (overrideProps = {}) => {
  const {user, ...utils} = render(<SearchBar {...getSearchBarProps()} {...overrideProps} />)
  return {user, ...utils}
}

describe('SearchBar Component', () => {
  test('renders the search bar with a placeholder', () => {
    renderSearchBar()

    const searchBarText = screen.getByTestId('search-bar')
    expect(searchBarText).toBeInTheDocument()
    expect(searchBarText).toHaveAttribute('placeholder', 'Search or filter organizations')
    expect(searchBarText).toHaveAttribute('aria-label', 'Search or filter organizations')
  })

  test('renders the search bar with a custom query value', () => {
    const customProps = {
      searchQuery: 'org1',
    }
    renderSearchBar(customProps)

    const searchBarText = screen.getByTestId('search-bar')
    expect(searchBarText).toBeInTheDocument()
    expect(searchBarText).toHaveValue('org1')
  })

  test('updates the query value when a user types in the search bar', async () => {
    const searchBarProps = getSearchBarProps()
    const setSearchQuerySpy = jest.spyOn(searchBarProps, 'setSearchQuery') // Spy on the setSearchQuery method

    const {user} = renderSearchBar(searchBarProps)

    const searchBarText = screen.getByTestId('search-bar')
    expect(searchBarText).toBeInTheDocument()

    // Simulate typing in the search bar
    await user.type(searchBarText, 'o')

    // Verify that the setSearchQuery method was called with the correct value
    expect(setSearchQuerySpy).toHaveBeenCalledTimes(1)
    expect(setSearchQuerySpy).toHaveBeenCalledWith('o')
  })
})
