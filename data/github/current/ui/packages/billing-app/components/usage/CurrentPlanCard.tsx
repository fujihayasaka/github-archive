import {Box, Button, Link, Heading, Text} from '@primer/react'
import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, Fonts} from '../../utils/style'
import {useParams} from 'react-router-dom'
import type {Customer} from '../../types/common'

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
  mb: 2,
}

interface CurrentPlanCardProps {
  customer: Customer
}

export default function CurrentPlanCard({customer}: CurrentPlanCardProps) {
  const {organization} = useParams()
  const licensingUrl = `/organizations/${organization}/settings/licensing`
  const plansUrl = `/organizations/${organization}/billing/plans`
  const isFreePlan = customer.plan === 'free_organization'

  let planName = 'N/A'
  switch (customer.plan) {
    case 'team': {
      planName = 'GitHub Team'
      break
    }
    case 'free_organization': {
      planName = 'GitHub Free'
      break
    }
    default: {
      planName = 'N/A'
      break
    }
  }

  return (
    <Box sx={cardStyle} data-testid="current-plan-card">
      <Box sx={{display: 'flex', alignItems: 'center'}}>
        <Heading as="h3" sx={{...cardHeadingStyle, flex: 'auto'}}>
          Current plan - {planName}
        </Heading>

        <>
          {isFreePlan ? (
            <Button as="a" href={plansUrl} variant={'primary'}>
              Upgrade
            </Button>
          ) : (
            <Link href={licensingUrl} sx={{fontSize: Fonts.FontSizeSmall}}>
              Manage plan
            </Link>
          )}
        </>
      </Box>
      <Box sx={moneyContainerStyle} data-testid="bill-section">
        <div>
          <Text sx={{mr: 2, fontSize: 4}}>{formatMoneyDisplay(customer.paymentAmount)}</Text>
          <Text sx={{mr: 2, fontSize: 2}}>per {customer.planDuration}</Text>
        </div>
      </Box>
      <>
        {isFreePlan ? (
          <Text as="p" sx={{mb: 0, color: 'fg.muted', fontSize: Fonts.FontSizeSmall}} data-testid="licenses-section">
            GitHub Free plan offers basics for organizations and developers.{' '}
            <Link href={plansUrl} inline>
              See all features and compare plans
            </Link>
          </Text>
        ) : (
          <Text as="p" sx={{mb: 0, color: 'fg.muted', fontSize: Fonts.FontSizeSmall}} data-testid="licenses-section">
            <Text sx={{fontWeight: 'bold'}}>{customer.seats}</Text> licenses -
            <Text sx={{fontWeight: 'bold'}}>{formatMoneyDisplay(customer.pricePerSeat)}</Text> per user/
            {customer.planDuration}
          </Text>
        )}
      </>
    </Box>
  )
}
