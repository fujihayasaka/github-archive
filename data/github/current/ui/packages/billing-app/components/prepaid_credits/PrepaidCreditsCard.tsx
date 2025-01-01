import {CreditCardIcon} from '@primer/octicons-react'
import {Link, CircleBadge, Text} from '@primer/react'
import {formatMoneyDisplay} from '../../utils/money'

const iconTextStyle = {position: 'relative', left: '60px', bottom: '40px'}
const CONTACT_SALES_LINK = 'https://github.com/enterprise/contact'

export interface PrepaidCreditsCardProps {
  prepaidCreditsBalance?: number
}

export default function PrepaidCreditsCard(props: PrepaidCreditsCardProps) {
  const balance = props.prepaidCreditsBalance || 0.0
  return (
    <div data-testid="prepaid-credits-card">
      <CircleBadge variant={'small'} sx={{backgroundColor: 'var(--display-blue-bgColor-muted)'}}>
        <CircleBadge.Icon icon={CreditCardIcon} />
      </CircleBadge>
      <Text sx={iconTextStyle}>
        You have {`${formatMoneyDisplay(balance)}`} remaining in prepaid credits.{' '}
        <Link inline href={CONTACT_SALES_LINK}>
          Contact GitHub sales
        </Link>{' '}
        or your reseller/distributor to increase the balance
      </Text>
    </div>
  )
}
