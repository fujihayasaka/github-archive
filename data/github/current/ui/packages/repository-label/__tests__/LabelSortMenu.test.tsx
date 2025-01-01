import {LabelSortMenu} from '../LabelSortMenu'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

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

describe('LabelSortMenu', () => {
  test('renders with default sort option and direction', async () => {
    const {user} = render(<LabelSortMenu />)

    const sortButton = screen.getByRole('button', {name: /sort/i})
    expect(sortButton).toBeInTheDocument()

    await user.click(sortButton)

    const menu = screen.getByRole('menu')
    expect(menu).toBeInTheDocument()

    const nameOption = screen.getByRole('menuitemradio', {name: /name/i})
    // const countOption = screen.getByRole('menuitemradio', {name: /total issue count/i})
    const ascendingOption = screen.getByRole('menuitemradio', {name: /ascending/i})
    const descendingOption = screen.getByRole('menuitemradio', {name: /descending/i})

    expect(nameOption).toBeInTheDocument()
    // expect(countOption).toBeInTheDocument()
    expect(ascendingOption).toBeInTheDocument()
    expect(descendingOption).toBeInTheDocument()

    expect(nameOption).toHaveAttribute('aria-checked', 'true')
    // expect(countOption).toHaveAttribute('aria-checked', 'false')
    expect(ascendingOption).toHaveAttribute('aria-checked', 'true')
    expect(descendingOption).toHaveAttribute('aria-checked', 'false')
  })

  test('updates URL when issue count option is selected', async () => {
    const {user} = render(<LabelSortMenu />)

    const sortButton = screen.getByRole('button', {name: /sort/i})

    await user.click(sortButton)

    const countOption = screen.getByRole('menuitemradio', {name: /total issue count/i})
    await user.click(countOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=count-desc')
  })

  test('updates URL when direction is selected as desc', async () => {
    const {user} = render(<LabelSortMenu />)

    const sortButton = screen.getByRole('button', {name: /sort/i})

    await user.click(sortButton)

    const descendingOption = screen.getByRole('menuitemradio', {name: /descending/i})
    await user.click(descendingOption)

    expect(navigateFn).toHaveBeenCalledWith('/?sort=name-desc')
  })
})
