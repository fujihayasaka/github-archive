import toUpper from 'lodash-es/toUpper'
import toLower from 'lodash-es/toLower'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {AnchoredOverlay, Box, Heading, IconButton, Link, Stack, Text} from '@primer/react'
import {InfoIcon} from '@primer/octicons-react'

import {ErrorComponent} from '..'

import {RequestState, UsagePeriod} from '../../enums'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, viewDetailsStyle} from '../../utils/style'
import useRoute from '../../hooks/use-route'
import {
  COPILOT_MANAGE_POLICIES_BASE_ROUTE,
  COPILOT_MANAGE_POLICIES_BASE_ROUTE_ORGS,
  ENTERPRISE_LICENSING_BASE_ROUTE,
  USAGE_ROUTE,
} from '../../routes'
import {GROUP_BY_SKU_TYPE, Products} from '../../constants'
import type {Filters} from '../../types/usage'
import {useContext, useState} from 'react'
import styles from './UsageInfoTile.module.css'
import {PageContext} from '../../App'

export const UsageInfoTileVariant = {
  amountSpent: 'AMOUNT_SPENT',
  quantityUsed: 'QUANTITY_USED',
  Overage: 'OVERAGE',
} as const

export type UsageInfoTileVariant = (typeof UsageInfoTileVariant)[keyof typeof UsageInfoTileVariant]

interface UsageInfoTileProps {
  filters: Filters
  isCopilotStandalone: boolean
  productName: string
  requestState: RequestState
  totalSpend?: number
  totalQuantity?: number
  variant: UsageInfoTileVariant
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

const isLoadingStates = new Set<RequestState>([RequestState.INIT, RequestState.LOADING])

export default function UsageInfoTile({
  filters,
  isCopilotStandalone,
  productName,
  requestState,
  totalSpend = 0,
  totalQuantity = 0,
  variant,
  codingAgentEnabled,
  sparkEnabled,
}: UsageInfoTileProps) {
  const {path: usageUrl} = useRoute(
    USAGE_ROUTE,
    {},
    {
      group: GROUP_BY_SKU_TYPE.toString(),
      period: filters?.period?.type?.toString() ?? UsagePeriod.DEFAULT.toString(),
      query: `product:${filters.product}`,
    },
  )

  const isEnterpriseRoute = useContext(PageContext).isEnterpriseRoute
  const isOrganizationRoute = useContext(PageContext).isOrganizationRoute
  const isUserRoute = useContext(PageContext).isUserRoute
  const {path: enterpriseLicensingUrl} = useRoute(ENTERPRISE_LICENSING_BASE_ROUTE)
  const {path: copilotPoliciesUrl} = useRoute(COPILOT_MANAGE_POLICIES_BASE_ROUTE)
  const {path: organizationCopilotPoliciesUrl} = useRoute(COPILOT_MANAGE_POLICIES_BASE_ROUTE_ORGS)
  const copilotUrl = determineCopilotUrl(
    isEnterpriseRoute,
    isOrganizationRoute,
    isUserRoute,
    copilotPoliciesUrl,
    organizationCopilotPoliciesUrl,
  )

  const [hintOpen, setHintOpen] = useState(false)

  function toTitleCase(str: string): string {
    return str
      .split(' ')
      .map(word => toUpper(word.charAt(0)) + toLower(word.slice(1)))
      .join(' ')
  }

  const capitalizedProductName = toTitleCase(productName)
  function defaultTitle(): string {
    if (productName === Products.models) {
      return `GitHub Models`
    } else if (variant === UsageInfoTileVariant.amountSpent) {
      return `${capitalizedProductName} usage`
    } else if (variant === UsageInfoTileVariant.Overage) {
      return `Copilot premium requests`
    } else {
      return `Billable licenses`
    }
  }

  function defaultSubtitle() {
    if (productName === Products.models) {
      return `Cost calculated based on additional ${totalQuantity} tokens`
    }

    if (variant === UsageInfoTileVariant.amountSpent) {
      return `Total spend on ${capitalizedProductName} for the selected timeframe, excluding applicable discounts.`
    }

    if (variant === UsageInfoTileVariant.Overage) {
      const baseMessage = `Cost calculated based on additional ${totalQuantity} premium requests`
      if (codingAgentEnabled && sparkEnabled) {
        return `${baseMessage} for Copilot, Spark and Copilot coding agent.`
      }
      if (codingAgentEnabled) {
        return `${baseMessage} for Copilot and Copilot coding agent.`
      }
      if (sparkEnabled) {
        return `${baseMessage} for Copilot and Spark.`
      }
      return baseMessage
    }

    return 'Showing total unique licenses billed for your enterprise. Actual billed amount for each license is prorated based on when it is added during the billing cycle.'
  }

  function spotlightedValue() {
    if (variant === UsageInfoTileVariant.amountSpent || variant === UsageInfoTileVariant.Overage) {
      return formatMoneyDisplay(totalSpend)
    }
    if (filters.period?.type === UsagePeriod.THIS_MONTH) {
      return totalQuantity.toLocaleString('default', {maximumFractionDigits: 0})
    }
    return undefined
  }

  function viewDetailsLink() {
    if (variant === UsageInfoTileVariant.quantityUsed && filters.product === Products.copilot && !isCopilotStandalone) {
      return null
    }
    const url =
      variant === UsageInfoTileVariant.amountSpent || variant === UsageInfoTileVariant.Overage
        ? usageUrl
        : enterpriseLicensingUrl
    return (
      <Link className="f6 ml-auto" href={url} sx={{...viewDetailsStyle}}>
        View details
      </Link>
    )
  }

  function determineCopilotUrl(
    isEnterprise: boolean,
    isOrganization: boolean,
    isUser: boolean,
    enterpriseRoute: string,
    organizationRoute: string,
  ) {
    if (isEnterprise) {
      const addPoliciesTab = `?tab=policies`
      const enterpriseCopilotPoliciesUrl = `${enterpriseRoute}${addPoliciesTab}`
      return enterpriseCopilotPoliciesUrl
    }

    if (isOrganization) {
      return organizationRoute
    }

    if (isUser) {
      return enterpriseRoute
    }
  }

  function hint() {
    if (variant === UsageInfoTileVariant.amountSpent) {
      return null
    } else if (variant === UsageInfoTileVariant.Overage) {
      return (
        <AnchoredOverlay
          align="center"
          open={hintOpen}
          onOpen={() => setHintOpen(true)}
          onClose={() => setHintOpen(false)}
          renderAnchor={props => (
            <IconButton
              aria-label="About Copilot premium requests"
              aria-labelledby={undefined}
              icon={InfoIcon}
              size="small"
              sx={{marginTop: '-2px'}}
              variant="invisible"
              {...props}
            />
          )}
          side="outside-top"
          width="medium"
        >
          <Stack direction="vertical" gap="normal" justify="center" padding="normal">
            <Text size="medium" weight="semibold" className={styles.textWrapper}>
              Copilot premium requests
            </Text>
            <Text size="medium" className={styles.OverlayText}>
              If enabled, additional premium requests beyond the included amount for each license will be billed.
            </Text>
            <Link href={copilotUrl}>Manage policy</Link>
          </Stack>
        </AnchoredOverlay>
      )
    }
    return (
      <AnchoredOverlay
        align="center"
        open={hintOpen}
        onOpen={() => setHintOpen(true)}
        onClose={() => setHintOpen(false)}
        renderAnchor={props => (
          <IconButton
            aria-label="About billable licenses"
            aria-labelledby={undefined}
            icon={InfoIcon}
            size="small"
            sx={{marginTop: '-2px'}}
            variant="invisible"
            {...props}
          />
        )}
        side="outside-top"
        width="medium"
      >
        <Stack direction="vertical" gap="normal" justify="center" padding="normal">
          <Text size="medium" weight="semibold">
            Billable licenses
          </Text>
          <Text size="medium" className={styles.OverlayText}>
            If a user stops consuming a license within the month, the adjustment will be reflected in your next
            month&apos;s bill.
          </Text>
          <Text size="medium" className={styles.OverlayText}>
            Billable licenses are only available for the &apos;Current month&apos; timeframe.
          </Text>
          <Link
            href="https://docs.github.com/enterprise-cloud@latest/billing/using-the-new-billing-platform/about-usage-based-billing-for-licenses"
            target="_blank"
            rel="noopener noreferrer"
          >
            Learn more
          </Link>
        </Stack>
      </AnchoredOverlay>
    )
  }

  return (
    <Box sx={boxStyle}>
      <div className="d-flex">
        <Heading as="h3" sx={{...cardHeadingStyle, mr: 1}}>
          {defaultTitle()}
        </Heading>
        {hint()}
        {viewDetailsLink()}
      </div>
      {isLoadingStates.has(requestState) && (
        <>
          <LoadingSkeleton variant="rounded" height="36px" />
          <LoadingSkeleton variant="rounded" height="xl" />
        </>
      )}
      {requestState === RequestState.ERROR && (
        <ErrorComponent sx={{border: 0}} testid={`${productName}-usage-loading-error`} text="Something went wrong" />
      )}
      {requestState === RequestState.IDLE && (
        <Text
          sx={{
            display: 'block',
            fontSize: 4,
            lineHeight: '36px',
            color: spotlightedValue() ? 'fg.default' : 'fg.muted',
          }}
          data-testid="number-display"
        >
          {spotlightedValue() ?? '-'}
        </Text>
      )}
      <Text as="p" sx={{mb: 0, color: 'fg.muted'}}>
        {defaultSubtitle()}
      </Text>
    </Box>
  )
}
