import {useContext, useEffect, useState} from 'react'
import {Box, Heading, Text} from '@primer/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, Fonts} from '../../utils/style'
import {UsageOverviewListDialog} from '.'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {LoadingComponent} from '..'
import {useParams} from 'react-router-dom'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {TOTAL_USAGE_ROUTE, matchBaseRouteByPath, findRouteBestMatchByPath} from '../../routes'
import useRoute from '../../hooks/use-route'

import type {CustomerSelection} from '../../types/usage'
import {PageContext} from '../../App'

const cardStyle = {
  ...boxStyle,
  display: 'flex',
  flexDirection: 'column',
}

const moneyContainerStyle = {
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'space-between',
  mb: 2,
}

interface TotalUsageCardProps {
  customerSelections: CustomerSelection[]
  isOrgAdmin?: boolean
}

const getRoute = (customerSelection: CustomerSelection, params: object): string => {
  const pathname = ssrSafeLocation.pathname
  let newPath =
    matchBaseRouteByPath(pathname)
      ?.childRoute(TOTAL_USAGE_ROUTE.fullPath)
      .generateFullPath({...params}) ?? ''

  const matchingRoute = findRouteBestMatchByPath(newPath)
  if (!matchingRoute) newPath = TOTAL_USAGE_ROUTE.fullPath

  const queryParamString = new URLSearchParams({customer_id: customerSelection.id}).toString()
  return `${newPath}?${queryParamString}`
}

const getUsageDisclaimer = (isOrganization: boolean, isOrgAdmin?: boolean, isEnterprise?: boolean): string => {
  switch (true) {
    case isOrganization:
      return 'Showing gross metered usage for your organization.'
    case isOrgAdmin:
      return 'Showing gross metered usage for all organizations which you own.'
    case isEnterprise:
      return 'Showing gross metered usage for your enterprise including all cost centers.'
    default:
      return 'Showing gross metered usage for your account.'
  }
}

export default function TotalUsageCard({customerSelections, isOrgAdmin}: TotalUsageCardProps) {
  const {path: requestUsageTotalsRoute} = useRoute(TOTAL_USAGE_ROUTE)
  const params = useParams()
  const [totalUsage, setTotalUsage] = useState(0)
  const [isLoadingTotalUsage, setLoadingTotalUsage] = useState(true)
  const [usageMap, setUsageMap] = useState<Record<string, number>>({})
  const {isEnterpriseRoute, isOrganizationRoute} = useContext(PageContext)

  useEffect(() => {
    const loadUsageData = async () => {
      const promises = customerSelections.map(async customerSelection => {
        const route = getRoute(customerSelection, params)
        const res = await verifiedFetchJSON(route, {
          method: 'GET',
        })
        return {res, id: customerSelection.id}
      })
      const results = await Promise.all(promises)
      let totalUsageTemp = 0
      const usageMapTemp: Record<string, number> = {}
      for (const {res, id} of results) {
        if (res.ok) {
          const data = await res.json()
          totalUsageTemp += data.usage.billableAmount
          usageMapTemp[id] = data.usage.billableAmount
        }
      }
      setTotalUsage(totalUsageTemp)
      setUsageMap(usageMapTemp)
      setLoadingTotalUsage(false)
    }

    const loadEnterpriseUsageData = async () => {
      const usageMapTemp: Record<string, number> = {}

      const res = await verifiedFetchJSON(requestUsageTotalsRoute, {method: 'GET'})
      if (res.ok) {
        const data = await res.json()
        setTotalUsage(data.usage.totalGrossAmount)

        for (const usage of data.usage.totals) {
          usageMapTemp[usage.name] = usage.grossAmount
        }
      }

      setLoadingTotalUsage(false)
      setUsageMap(usageMapTemp)
    }

    if (isEnterpriseRoute) {
      loadEnterpriseUsageData()
    } else {
      loadUsageData()
    }

    // Disable the eslint rule below because:
    // customerSelections is passed with the SSR payload and will not change
    // params can change but changes in the params should not trigger a re-fetch of TotalUsage data
    // since it is always fetched for the current month across all products for the selected customer
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <Box sx={cardStyle}>
      <Box sx={{display: 'flex', alignItems: 'center'}}>
        <Heading as="h2" sx={{...cardHeadingStyle, flex: 'auto'}}>
          Current metered usage
        </Heading>
        {!isLoadingTotalUsage && isEnterpriseRoute && (
          <UsageOverviewListDialog totalUsage={totalUsage} usageMap={usageMap} />
        )}
      </Box>
      <>
        <Box sx={isLoadingTotalUsage ? {display: 'block', width: '50%'} : moneyContainerStyle}>
          <div>
            {isLoadingTotalUsage ? (
              <Box sx={{display: 'flex', justifyContent: 'space-between', py: 2, mr: 3}}>
                <LoadingComponent sx={{p: 0, border: 0}}>
                  <LoadingSkeleton sx={{flex: 1}} variant="rounded" height="md" />
                </LoadingComponent>
              </Box>
            ) : (
              <Text sx={{mr: 2, fontSize: 4}} data-testid="total-discount">
                {formatMoneyDisplay(totalUsage)}
              </Text>
            )}
          </div>
        </Box>
        <Text as="p" sx={{mb: 0, color: 'fg.muted', fontSize: Fonts.FontSizeSmall}} data-testid="usage-disclaimer">
          {getUsageDisclaimer(isOrganizationRoute, isOrgAdmin, isEnterpriseRoute)}
        </Text>
      </>
    </Box>
  )
}
