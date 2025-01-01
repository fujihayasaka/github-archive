import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {OwnerDropdownItemsV2} from '../OwnerDropdownItemsV2'
import {ownerItems} from './test-helpers'

describe('OwnerDropdownItemsV2', () => {
  test('shows blankslate if no filter results', async () => {
    render(<OwnerDropdownItemsV2 ownerItems={[]} onSelect={jest.fn()} searchTerm="foo" />)

    expect(screen.getByText('No owners found for `foo`')).toBeInTheDocument()
    expect(screen.getByText('Adjust your search term to find other owners')).toBeInTheDocument()
  })

  test('strips off surrounding parentheses on inactive text', async () => {
    const inactiveOwnerItem = {...ownerItems[0]!, disabled: true, customDisabledMessage: '(got parentheses)'}

    render(<OwnerDropdownItemsV2 ownerItems={[inactiveOwnerItem]} onSelect={jest.fn()} searchTerm="foo" />)

    expect(screen.getByText('got parentheses')).toBeInTheDocument()
  })

  test('displays inactive text as-is if not surrounded by parentheses', async () => {
    const inactiveOwnerItem = {...ownerItems[0]!, disabled: true, customDisabledMessage: '(has one parenthesis'}

    render(<OwnerDropdownItemsV2 ownerItems={[inactiveOwnerItem]} onSelect={jest.fn()} searchTerm="foo" />)

    expect(screen.getByText('(has one parenthesis')).toBeInTheDocument()
  })
})
