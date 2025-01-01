import {render} from '@github-ui/react-core/test-utils'

// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor} from '@testing-library/react'

import {DiscountUsageCard} from '../../components/usage'

import {MOCK_PRODUCT_ACTIONS, MOCK_PRODUCT_LFS} from '../../test-utils/mock-data'
import {MOCK_DISCOUNTS, MOCK_DISCOUNTS_WITH_FREE_PUBLIC_REPO} from '../../test-utils/mock-discount-data'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: '/enterprises/github-inc/billing'}
    })()
  },
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => {
    return {business: 'github-inc'}
  },
}))

describe('DiscountUsageCard', () => {
  const month = new Date().getUTCMonth() + 1
  const year = new Date().getUTCFullYear()
  const discountRoute = `/enterprises/github-inc/billing/discounts?month=${month}&year=${year}`

  test('Renders the discount usage card for one product', async () => {
    mockFetch.mockRouteOnce(discountRoute, {discounts: MOCK_DISCOUNTS})

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS]}
        isOrganization={false}
        isUser={false}
        isEnterpriseOrgOwner={false}
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await waitFor(() => expect(screen.getByTestId('total-discount')).toHaveTextContent('$396.00'))
    await expect(
      screen.findByText('Showing currently applied discounts for your enterprise.'),
    ).resolves.toBeInTheDocument()
  })
  test('Renders the discount usage card for two products', async () => {
    mockFetch.mockRouteOnce(discountRoute, {discounts: MOCK_DISCOUNTS})

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS, MOCK_PRODUCT_LFS]}
        isOrganization={false}
        isUser={false}
        isEnterpriseOrgOwner={false}
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await waitFor(() => expect(screen.getByTestId('total-discount')).toHaveTextContent('$426.00'))
  })

  test('Renders the free for public repo discount when there is one', async () => {
    mockFetch.mockRouteOnce(discountRoute, {
      discounts: MOCK_DISCOUNTS_WITH_FREE_PUBLIC_REPO,
    })

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS]}
        isOrganization={false}
        isUser={false}
        isEnterpriseOrgOwner={false}
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await waitFor(() => expect(screen.getByTestId('total-discount')).toHaveTextContent('$60.00'))
  })

  test('Renders the relevant discount text for enterprise org owner', async () => {
    mockFetch.mockRouteOnce(discountRoute, {
      discounts: MOCK_DISCOUNTS_WITH_FREE_PUBLIC_REPO,
    })

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS]}
        isOrganization={false}
        isUser={false}
        isEnterpriseOrgOwner
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await expect(
      screen.findByText('Showing currently applied discounts for your organization(s).'),
    ).resolves.toBeInTheDocument()
  })

  test('Renders the relevant discount text for org owner', async () => {
    mockFetch.mockRouteOnce(discountRoute, {
      discounts: MOCK_DISCOUNTS_WITH_FREE_PUBLIC_REPO,
    })

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS]}
        isOrganization
        isUser={false}
        isEnterpriseOrgOwner={false}
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await expect(
      screen.findByText('Showing currently applied discounts for your organization.'),
    ).resolves.toBeInTheDocument()
  })

  test('Renders the relevant discount text for individual user', async () => {
    mockFetch.mockRouteOnce(discountRoute, {
      discounts: MOCK_DISCOUNTS_WITH_FREE_PUBLIC_REPO,
    })

    render(
      <DiscountUsageCard
        enabledProducts={[MOCK_PRODUCT_ACTIONS]}
        isOrganization={false}
        isUser
        isEnterpriseOrgOwner={false}
        isCopilotPremiumUsageReportEnabled={false}
      />,
    )

    await expect(
      screen.findByText('Showing currently applied discounts for your account.'),
    ).resolves.toBeInTheDocument()
  })
})
