import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {MilestoneSortMenu} from '../MilestoneSortMenu'

const navigateFn = jest.fn()
let mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
    useSearchParams: () => mockUseSearchParams,
  }
})

beforeEach(() => {
  navigateFn.mockClear()
  mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
})

describe('MilestoneSortMenu', () => {
  test('renders the default option', async () => {
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)
    const recentlyOption = screen.getByRole('menuitemradio', {name: /recently updated/i})
    expect(recentlyOption).toBeInTheDocument()
    expect(recentlyOption).toBeChecked()

    const dueDateOption = screen.getByRole('menuitemradio', {name: /furthest due date/i})
    expect(dueDateOption).toBeInTheDocument()
    expect(dueDateOption).not.toBeChecked()
    await user.click(dueDateOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=due_date&direction=desc')
  })

  test('verify due to is rendered correctly', async () => {
    mockUseSearchParams = [new URLSearchParams('sort=due_date&direction=desc'), jest.fn()]
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)
    const recentlyOption = screen.getByRole('menuitemradio', {name: /furthest due date/i})
    expect(recentlyOption).toBeInTheDocument()
    expect(recentlyOption).toBeChecked()

    const dueDateOption = screen.getByRole('menuitemradio', {name: /closest due date/i})
    expect(dueDateOption).toBeInTheDocument()
    expect(dueDateOption).not.toBeChecked()
    await user.click(dueDateOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=due_date&direction=asc')
  })

  test('renders and selects alphabetical sort option', async () => {
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)

    const alphabeticalOption = screen.getByRole('menuitemradio', {name: 'Alphabetical'})
    expect(alphabeticalOption).toBeInTheDocument()
    expect(alphabeticalOption).not.toBeChecked()
    await user.click(alphabeticalOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=title&direction=asc')
  })

  test('renders and selects reverse alphabetical sort option', async () => {
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)

    const reverseAlphabeticalOption = screen.getByRole('menuitemradio', {name: /reverse alphabetical/i})
    expect(reverseAlphabeticalOption).toBeInTheDocument()
    expect(reverseAlphabeticalOption).not.toBeChecked()
    await user.click(reverseAlphabeticalOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=title&direction=desc')
  })

  test('renders and selects most issues sort option', async () => {
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)

    const mostIssuesOption = screen.getByRole('menuitemradio', {name: /most issues/i})
    expect(mostIssuesOption).toBeInTheDocument()
    expect(mostIssuesOption).not.toBeChecked()
    await user.click(mostIssuesOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=count&direction=desc')
  })

  test('renders and selects least issues sort option', async () => {
    const {user} = render(<MilestoneSortMenu />)
    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()
    await user.click(sortButton)

    const leastIssuesOption = screen.getByRole('menuitemradio', {name: /fewest issues/i})
    expect(leastIssuesOption).toBeInTheDocument()
    expect(leastIssuesOption).not.toBeChecked()
    await user.click(leastIssuesOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=count&direction=asc')
  })
})
