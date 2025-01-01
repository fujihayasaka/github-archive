import {Box, Heading, Text, Link, Button, Label} from '@primer/react'

import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, Fonts} from '../../utils/style'
import {paymentDueCopyContainerStyle} from './PaymentDueCard'
import {PageContext} from '../../App'
import {useContext} from 'react'

export interface NextPaymentCardProps {
  nextPaymentDate: string | null
  autoPayDisabled: boolean
  hasBill: boolean
  meteredViaAzure: boolean
  overdue: boolean
  latestBillAmount: number
  rbiPaymentLink: string
  nextChargeAmount: number
}

const INDIA_RBI_DOC_LINK =
  'https://docs.github.com/billing/managing-the-plan-for-your-github-account/one-time-payments-for-customers-in-india'

export default function NextPaymentCard(props: NextPaymentCardProps) {
  const {isOrganizationRoute, isUserRoute} = useContext(PageContext)
  const getPaymentHistoryLink = () => {
    return isUserRoute ? '../account/billing/history' : '../billing/history'
  }
  return (
    <Box sx={boxStyle} data-testid="next-payment-card">
      <Box sx={{display: 'flex', justifyContent: 'space-between'}}>
        <Heading as="h3" sx={{...cardHeadingStyle, fontSize: Fonts.FontSizeNormal}}>
          Next payment due
        </Heading>

        {props.autoPayDisabled && props.nextChargeAmount > 0 ? (
          <>
            <div>
              <Button as="a" href={props.rbiPaymentLink} variant="primary" size="small">
                Pay now
              </Button>
            </div>
          </>
        ) : (
          <Link href={getPaymentHistoryLink()} sx={{fontSize: Fonts.FontSizeSmall}}>
            Payment history
          </Link>
        )}
      </Box>

      {
        <Box sx={{mb: 2, display: 'flex', alignItems: 'center', gap: 2}}>
          {!props.autoPayDisabled ? (
            <div>
              <Text sx={{fontSize: 4}} data-testid="next-payment-date">
                {props.nextPaymentDate || '-'}
              </Text>
            </div>
          ) : (
            <div>
              <Text sx={{fontSize: 4}}>{formatMoneyDisplay(props.nextChargeAmount)} </Text>
              <Text sx={{color: 'fg.muted'}}>
                {!props.overdue && props.nextChargeAmount > 0 && <> by {props.nextPaymentDate}</>}
              </Text>
              <span>{props.overdue && <Label variant="attention">Overdue</Label>}</span>
            </div>
          )}
        </Box>
      }

      <Box sx={paymentDueCopyContainerStyle}>
        {props.meteredViaAzure && isOrganizationRoute && <p>Metered usage billed via Azure is not included.</p>}
        {props.autoPayDisabled && (
          <p>
            Automatic{' '}
            <Link inline href={INDIA_RBI_DOC_LINK} sx={{color: 'fg.muted'}} target="_blank">
              recurring payments are disabled
            </Link>
            .
          </p>
        )}
      </Box>
    </Box>
  )
}
