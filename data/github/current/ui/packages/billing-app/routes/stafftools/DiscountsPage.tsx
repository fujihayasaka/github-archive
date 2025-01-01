import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Heading} from '@primer/react'
import {useContext} from 'react'

import {PageContext} from '../../App'
import {DiscountForm} from '../../components/stafftools/discounts/DiscountForm'
import {DiscountUsageCard} from '../../components/usage'
import {pageHeadingStyle} from '../../utils'

import type {Customer} from '../../types/common'
import type {EnabledProduct} from '../../types/products'

export interface DiscountsPagePayload {
  customer: Customer
  enabledProducts: EnabledProduct[]
  isEnterpriseOrgOwner: boolean
}

export function DiscountsPage() {
  const {customer, enabledProducts, isEnterpriseOrgOwner} = useRoutePayload<DiscountsPagePayload>()
  const isOrganizationRoute = useContext(PageContext).isOrganizationRoute
  const isUserRoute = useContext(PageContext).isUserRoute

  return (
    <>
      <header className="Subhead">
        <Heading as="h2" className="Subhead-heading" sx={pageHeadingStyle}>
          Discounts
        </Heading>
      </header>
      <DiscountUsageCard
        enabledProducts={enabledProducts}
        isOrganization={isOrganizationRoute}
        isUser={isUserRoute}
        isEnterpriseOrgOwner={isEnterpriseOrgOwner}
      />
      <DiscountForm customer={customer} enabledProducts={enabledProducts} />
    </>
  )
}
