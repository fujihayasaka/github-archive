import {render, screen} from '@testing-library/react'
import {Filters, type CheckboxGroupProps} from '../../components/Filters/Filters'

describe('Filters Component', () => {
  let mockCheckboxGroup = Array<CheckboxGroupProps>()

  beforeEach(() => {
    jest.clearAllMocks()
    mockCheckboxGroup = [
      {
        name: 'test_group_1',
        label: 'Test Group 1',
        checkboxes: [
          {label: 'Checkbox 1', value: 'checkbox1', isChecked: false},
          {label: 'Checkbox 2', value: 'checkbox2', isChecked: false},
        ],
      },
    ]
  })

  it('renders correctly with default props', () => {
    render(<Filters checkboxGroups={mockCheckboxGroup} />)

    expect(screen.getByRole('heading', {name: /filters/i})).toBeInTheDocument()
    expect(screen.getByText(/Checkbox 1/i)).toBeInTheDocument()
    expect(screen.getByText(/Checkbox 2/i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: /open filters/i})).toBeInTheDocument()
  })

  it('renders correctly when whitepaper filter is checked', () => {
    const whitepaperCheckedGroup = mockCheckboxGroup
    whitepaperCheckedGroup[0]!.checkboxes[0]!.isChecked = true
    render(<Filters checkboxGroups={whitepaperCheckedGroup} />)

    expect(screen.getByRole('checkbox', {name: /checkbox 1/i})).toBeChecked()
    expect(screen.getByRole('checkbox', {name: /checkbox 2/i})).not.toBeChecked()
    expect(screen.getByTestId('filters-heading')).toHaveTextContent('Filters (1)')
  })

  it('renders correctly when ebooks filter is checked', () => {
    const ebookCheckedGroup = mockCheckboxGroup
    ebookCheckedGroup[0]!.checkboxes[1]!.isChecked = true
    render(<Filters checkboxGroups={ebookCheckedGroup} />)

    expect(screen.getByRole('checkbox', {name: /checkbox 1/i})).not.toBeChecked()
    expect(screen.getByRole('checkbox', {name: /checkbox 2/i})).toBeChecked()
    expect(screen.getByTestId('filters-heading')).toHaveTextContent('Filters (1)')
  })

  it('renders correctly when both ebooks and whitepapers filters are checked', () => {
    const bothCheckedGroup = mockCheckboxGroup
    for (const checkbox of bothCheckedGroup[0]!.checkboxes) {
      checkbox.isChecked = true
    }

    render(<Filters checkboxGroups={bothCheckedGroup} />)

    expect(screen.getByRole('checkbox', {name: /checkbox 1/i})).toBeChecked()
    expect(screen.getByRole('checkbox', {name: /checkbox 2/i})).toBeChecked()
    expect(screen.getByTestId('filters-heading')).toHaveTextContent('Filters (2)')
  })
})
