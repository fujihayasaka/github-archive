import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {NestingTable} from '../../../components/NestingTable/NestingTable'

const defaultProps = {
  header: 'Heading text',
  children: 'Table body',
  'data-testid': 'test-id',
}

test('Renders NestingTable', () => {
  render(<NestingTable {...defaultProps} />)

  expect(screen.getByText(defaultProps.header)).toBeInTheDocument()
  // this isn't actually accessing a node, 'children' is a prop
  // eslint-disable-next-line testing-library/no-node-access
  expect(screen.getByText(defaultProps.children)).toBeInTheDocument()
  expect(screen.getByTestId(defaultProps['data-testid'])).toBeInTheDocument()
})
