import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {NoteIcon} from '@primer/octicons-react'
import {NestingTableRow} from '../../../components/NestingTable/NestingTableRow'

const defaultProps = {
  leadingIcon: (
    <span data-testid="note-icon">
      <NoteIcon />
    </span>
  ),
  title: 'Title text',
}

const subItems = [
  <NestingTableRow
    key="1"
    leadingIcon={<NoteIcon />}
    title="Sublist item 1"
    description="Sublist item 1 description"
  />,
  <NestingTableRow
    key="2"
    leadingIcon={<NoteIcon />}
    title="Sublist item 2"
    description="Sublist item 2 description"
  />,
]

test('Renders NestingTableRow', () => {
  render(<NestingTableRow {...defaultProps} />)

  expect(screen.getByText(defaultProps.title)).toBeInTheDocument()
  expect(screen.getByTestId('note-icon')).toBeInTheDocument()
  // Description and title label should not be rendered if not provided
  expect(screen.queryByTestId('description')).not.toBeInTheDocument()
  expect(screen.queryByTestId('title-label')).not.toBeInTheDocument()
})

test('Renders description when string value provided', () => {
  render(<NestingTableRow {...defaultProps} description="description" />)
  expect(screen.getByTestId('description')).toBeInTheDocument()
})

test('Renders description when ReactNode provided', () => {
  // ReactNode value
  render(<NestingTableRow {...defaultProps} description={<span>description</span>} />)
  expect(screen.getByTestId('description')).toBeInTheDocument()
})

test('Does not render description if it is an empty string', () => {
  render(<NestingTableRow {...defaultProps} description="" />)

  expect(screen.queryByTestId('description')).not.toBeInTheDocument()
})

test('Renders sublist and toggle when sublist is provided, toggle toggles visibility', async () => {
  const {user} = render(<NestingTableRow {...defaultProps} subItems={subItems} />)

  expect(screen.getByTestId('sublist-toggle')).toBeInTheDocument()
  const toggleButton = within(screen.getByTestId('sublist-toggle')).getByRole('button')

  // Sublist is hidden by default
  expect(screen.queryByTestId('sublist')).not.toBeInTheDocument()

  // Clicking the toggle button should make the sublist visible
  await user.click(toggleButton)
  expect(screen.getByTestId('sublist')).toBeInTheDocument()

  // Clicking the toggle button again should hide the sublist
  await user.click(toggleButton)
  expect(screen.queryByTestId('sublist')).not.toBeInTheDocument()
})

test('Renders trailing items when provided', () => {
  const trailingItems = [<span key="1">Trailing item 1</span>, <span key="2">Trailing item 2</span>]
  render(<NestingTableRow {...defaultProps} trailingItems={trailingItems} />)

  expect(screen.getByText('Trailing item 1')).toBeInTheDocument()
  expect(screen.getByText('Trailing item 2')).toBeInTheDocument()
})

test('Renders title label when provided', () => {
  render(<NestingTableRow {...defaultProps} titleLabel="Title label" />)

  expect(screen.getByTestId('title-label')).toHaveTextContent('Title label')
})
