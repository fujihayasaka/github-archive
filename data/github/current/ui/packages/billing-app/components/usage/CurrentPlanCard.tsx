import {Box, Link, Heading, Text, Button, Label} from '@primer/react'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, Fonts} from '../../utils/style'
import {useParams} from 'react-router-dom'
import type {Customer} from '../../types/common'
import {useContext} from 'react'
import {PageContext} from '../../App'
import pluralize from 'pluralize'

const cardStyle = {
  ...boxStyle,
  mb: 4,
  display: 'flex',
  flexDirection: 'column',
}

const moneyContainerStyle = {
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'space-between',
}

const subTextStyle = {
  mb: 0,
  mt: 2,
  color: 'fg.muted',
  fontSize: Fonts.FontSizeSmall,
}

interface CurrentPlanCardProps {
  customer: Customer
  changeDurationPath?: string
}

export default function CurrentPlanCard({customer, changeDurationPath}: CurrentPlanCardProps) {
  const {organization} = useParams()
  const {isOrganizationRoute} = useContext(PageContext)
  const licensingUrl = isOrganizationRoute
    ? `/organizations/${organization}/settings/licensing`
    : `/settings/billing/licensing`
  const plansUrl = isOrganizationRoute ? `/organizations/${organization}/billing/plans` : `/settings/billing/plans`
  const isFreePlan = customer.plan.startsWith('free_')
  const isProPlan = customer.plan === 'pro'

  const getPlanName = (plan: string): string => {
    if (plan.startsWith('free_')) {
      return 'GitHub Free'
    }
    switch (plan) {
      case 'team':
        return 'GitHub Team'
      case 'pro':
        return 'GitHub Pro'
      default:
        return 'N/A'
    }
  }

  const getAlternatePlanDuration = (planDuration: string): string => {
    if (planDuration === 'month') {
      return 'yearly'
    } else {
      return 'monthly'
    }
  }

  return (
    <Box sx={cardStyle} data-testid="current-plan-card">
      <Box sx={{display: 'flex', justifyContent: 'space-between'}}>
        <div>
          <Box sx={{display: 'flex', alignItems: 'center'}}>
            <Heading as="h3" sx={{...cardHeadingStyle, flex: 'auto'}}>
              Current plan - {getPlanName(customer.plan)}
            </Heading>
            {customer.hasPendingPlanChange && <Label sx={{mb: 'auto', ml: 2}}>Downgrade Pending</Label>}
          </Box>
          <Box sx={moneyContainerStyle} data-testid="bill-section">
            <div>
              <Text sx={{mr: 2, fontSize: 4}}>{formatMoneyDisplay(customer.paymentAmount)}</Text>
              <Text sx={{mr: 2, fontSize: 2}}>per {customer.planDuration}</Text>
            </div>
          </Box>
        </div>

        <>
          {isFreePlan ? (
            <Button as="a" href={plansUrl} variant={'primary'}>
              Upgrade
            </Button>
          ) : (
            <Box sx={{display: 'flex', flexDirection: 'column'}}>
              <Link href={licensingUrl} sx={{fontSize: Fonts.FontSizeSmall}}>
                Manage plan
              </Link>
              {changeDurationPath && (
                <Link href={changeDurationPath} sx={{fontSize: Fonts.FontSizeSmall}} data-testid="cycle-switch-section">
                  Switch to {getAlternatePlanDuration(customer.planDuration)} billing
                </Link>
              )}
            </Box>
          )}
        </>
      </Box>

      {!isProPlan && (
        <>
          {isFreePlan ? (
            <Text as="p" sx={subTextStyle} data-testid="licenses-section">
              GitHub Free plan offers basics for organizations and developers.{' '}
              <Link href={plansUrl} inline>
                See all features and compare plans
              </Link>
            </Text>
          ) : (
            <Text as="p" sx={subTextStyle} data-testid="licenses-section">
              <Text sx={{fontWeight: 'bold'}}>{customer.seats}</Text> {pluralize('license', customer.seats)} -
              <Text sx={{fontWeight: 'bold'}}>{formatMoneyDisplay(customer.pricePerSeat)}</Text> per user/
              {customer.planDuration}
            </Text>
          )}
        </>
      )}
    </Box>
  )
}
