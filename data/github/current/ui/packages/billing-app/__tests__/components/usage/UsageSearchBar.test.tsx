import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {UsageSearchBar} from '../../../components/usage'

import {GITHUB_INC_CUSTOMER, ORGANIZATION_CUSTOMER, MOCK_PRODUCTS} from '../../../test-utils/mock-data'
import {PageContext} from '../../../App'
import {GROUP_BY_COSTCENTER_TYPE, GROUP_BY_NONE_TYPE, GROUP_BY_ORG_TYPE, GROUP_BY_SKU_TYPE} from '../../../constants'
import type {Customer} from '../../../types/common'
import type {UsageGrouping} from '../../../enums'

type SetupOptions = {
  customer?: Customer
  selectedGroup?: UsageGrouping
  isEnterpriseRoute?: boolean
  isOrganizationRoute?: boolean
}

function setup({
  customer = GITHUB_INC_CUSTOMER,
  selectedGroup = GROUP_BY_NONE_TYPE,
  isEnterpriseRoute = true,
  isOrganizationRoute = false,
}: SetupOptions = {}) {
  const setSearchQueryMock = jest.fn()
  const environment = createMockEnvironment()

  const utils = render(
    <RelayEnvironmentProvider environment={environment}>
      <PageContext.Provider
        value={{
          isStafftoolsRoute: false,
          isEnterpriseRoute,
          isOrganizationRoute,
          isUserRoute: false,
        }}
      >
        <UsageSearchBar
          searchQuery=""
          setSearchQuery={setSearchQueryMock}
          customer={customer}
          selectedGroup={selectedGroup}
          enabledProducts={MOCK_PRODUCTS}
        />
      </PageContext.Provider>
    </RelayEnvironmentProvider>,
  )

  return {
    ...utils,
    setSearchQueryMock,
  }
}

describe('UsageSearchBar', () => {
  test('Renders a usage search bar and updates the search query with input change', async () => {
    jest.useFakeTimers()

    const {setSearchQueryMock} = setup()

    const input = screen.getByRole('combobox') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(input, {target: {value: 'org:github'}})

    jest.runAllTimers()
    expect(setSearchQueryMock).toHaveBeenCalledTimes(1)
    expect(setSearchQueryMock).toHaveBeenCalledWith('org:github')
  })

  test('Renders a usage search bar and does not set the search query if there are two filters', async () => {
    const {user, setSearchQueryMock} = setup()

    const input = screen.getByRole('combobox')
    user.type(input, 'org:github repo:github')

    expect(setSearchQueryMock).toHaveBeenCalledTimes(0)
  })

  test('Does not add "organization" to suggested search filters if the customer is an organization', async () => {
    const {user} = setup({
      customer: ORGANIZATION_CUSTOMER,
      isOrganizationRoute: true,
      isEnterpriseRoute: false,
    })

    const input = screen.getByRole('combobox')
    await user.click(input)

    expect(input).toHaveAttribute('aria-expanded', 'true')

    const listbox = await screen.findByRole('listbox', {
      name: 'Suggestions',
    })

    expect(listbox).toBeInTheDocument()

    const repositoryFilter = await screen.findByText('Repository', {
      selector: '.ActionListItem-label',
    })
    const organizationFilter = screen.queryByText('Organization', {
      selector: '.ActionListItem-label',
    })

    expect(repositoryFilter).toBeInTheDocument()
    expect(organizationFilter).not.toBeInTheDocument()
  })

  test('Does not add product as a suggested search filter if the selected group is cost center', async () => {
    const {user} = setup({
      selectedGroup: GROUP_BY_COSTCENTER_TYPE,
    })

    const input = screen.getByRole('combobox')
    await user.click(input)

    expect(input).toHaveAttribute('aria-expanded', 'true')

    const listbox = await screen.findByRole('listbox', {
      name: 'Suggestions',
    })

    expect(listbox).toBeInTheDocument()

    const repositoryFilter = await screen.findByText('Repository', {
      selector: '.ActionListItem-label',
    })
    const productFilter = screen.queryByText('Product', {
      selector: '.ActionListItem-label',
    })

    expect(repositoryFilter).toBeInTheDocument()
    expect(productFilter).not.toBeInTheDocument()
  })

  test('Does not add SKU as a suggested search filter if the selected group is organization', async () => {
    const {user} = setup({
      selectedGroup: GROUP_BY_ORG_TYPE,
    })

    const input = screen.getByRole('combobox')
    await user.click(input)

    expect(input).toHaveAttribute('aria-expanded', 'true')

    const listbox = await screen.findByRole('listbox', {
      name: 'Suggestions',
    })

    expect(listbox).toBeInTheDocument()

    const costCenterFilter = await screen.findByText('Cost Center', {
      selector: '.ActionListItem-label',
    })
    const skuFilter = screen.queryByText('SKU', {
      selector: '.ActionListItem-label',
    })

    expect(costCenterFilter).toBeInTheDocument()
    expect(skuFilter).not.toBeInTheDocument()
  })

  test('Does not add SKU as a suggested search filter if the selected group is SKU', async () => {
    const {user} = setup({
      selectedGroup: GROUP_BY_SKU_TYPE,
    })

    const input = screen.getByRole('combobox')
    await user.click(input)

    expect(input).toHaveAttribute('aria-expanded', 'true')

    const listbox = await screen.findByRole('listbox', {
      name: 'Suggestions',
    })

    expect(listbox).toBeInTheDocument()

    const productFilter = await screen.findByText('Product', {
      selector: '.ActionListItem-label',
    })
    const skuFilter = screen.queryByText('SKU', {
      selector: '.ActionListItem-label',
    })

    expect(productFilter).toBeInTheDocument()
    expect(skuFilter).not.toBeInTheDocument()
  })
})
