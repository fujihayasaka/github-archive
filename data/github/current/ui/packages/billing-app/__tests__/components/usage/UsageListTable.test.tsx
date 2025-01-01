import {render, screen} from '@testing-library/react'
import UsageListTable from '../../../components/usage/UsageCard/UsageListTable' // Changed to default import
import {UsageCardVariant} from '../../../enums'
import type {RepoUsageLineItem} from '../../../types/usage'
import {PageContext} from '../../../App'

const mockRepoUsageData: RepoUsageLineItem[] = [
  {
    org: {
      name: 'github',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'github',
    },
    repo: {name: 'pac-man'},
    billedAmount: 100,
    product: 'actions',
    totalAmount: 100,
    discountAmount: 0,
    entityId: '1',
    quantity: 1000,
    fullQuantity: 1000,
    appliedCostPerQuantity: 0.1,
    usageAt: '2024-01-01T00:00:00Z',
    name: 'github/pac-man',
  },
]

const mockOrgUsageData: RepoUsageLineItem[] = [
  {
    org: {
      name: 'github',
      avatarSrc: 'https://avatars.githubusercontent.com/github',
      login: 'github',
    },
    repo: {name: ''},
    billedAmount: 100,
    product: 'actions',
    totalAmount: 100,
    discountAmount: 0,
    entityId: '1',
    quantity: 1000,
    fullQuantity: 1000,
    appliedCostPerQuantity: 0.1,
    usageAt: '2024-01-01T00:00:00Z',
    name: 'github',
  },
  {
    org: {
      name: 'primer',
      avatarSrc: 'https://avatars.githubusercontent.com/primer',
      login: 'primer',
    },
    repo: {name: ''},
    billedAmount: 200,
    product: 'actions',
    totalAmount: 200,
    discountAmount: 0,
    entityId: '2',
    quantity: 2000,
    fullQuantity: 2000,
    appliedCostPerQuantity: 0.1,
    usageAt: '2024-01-01T00:00:00Z',
    name: 'primer',
  },
]

describe('UsageListTable', () => {
  it('renders only repo name in REPO variant for user routes', () => {
    render(
      <PageContext.Provider
        value={{
          isUserRoute: true,
          isStafftoolsRoute: false,
          isOrganizationRoute: false,
          isEnterpriseRoute: false,
        }}
      >
        <UsageListTable usage={mockRepoUsageData} variant={UsageCardVariant.REPO} allOtherUsage={50} />
      </PageContext.Provider>,
    )

    // Check that only the repo name is displayed
    expect(screen.getByText('pac-man')).toBeInTheDocument()
    // Verify org name and full path are not displayed
    expect(screen.queryByText('github')).not.toBeInTheDocument()
    expect(screen.queryByText('github/pac-man')).not.toBeInTheDocument()
  })

  it('renders full org/repo path in REPO variant for org/enterprise routes', () => {
    render(
      <PageContext.Provider
        value={{
          isUserRoute: false,
          isStafftoolsRoute: false,
          isOrganizationRoute: true,
          isEnterpriseRoute: false,
        }}
      >
        <UsageListTable usage={mockRepoUsageData} variant={UsageCardVariant.REPO} allOtherUsage={50} />
      </PageContext.Provider>,
    )

    // Check that full org/repo path is displayed
    expect(screen.getByText('github/pac-man')).toBeInTheDocument()
    // Verify individual parts are not displayed separately
    expect(screen.queryByText('github')).not.toBeInTheDocument()
    expect(screen.queryByText('pac-man')).not.toBeInTheDocument()
  })

  it('renders organization names and amounts in ORG variant', () => {
    render(
      <PageContext.Provider
        value={{
          isUserRoute: false,
          isStafftoolsRoute: false,
          isOrganizationRoute: true,
          isEnterpriseRoute: false,
        }}
      >
        <UsageListTable usage={mockOrgUsageData} variant={UsageCardVariant.ORG} allOtherUsage={50} />
      </PageContext.Provider>,
    )

    // Check that organization names are displayed
    expect(screen.getByText('github')).toBeInTheDocument()
    expect(screen.getByText('primer')).toBeInTheDocument()

    // Check amounts are formatted correctly
    expect(screen.getByText('$100.00')).toBeInTheDocument()
    expect(screen.getByText('$200.00')).toBeInTheDocument()

    // Verify no repository information is displayed
    expect(screen.queryByText('github/')).not.toBeInTheDocument()
    expect(screen.queryByText('primer/')).not.toBeInTheDocument()
  })
})
