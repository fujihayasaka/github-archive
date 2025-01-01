import {Heading, Button, Link} from '@primer/react'

import styles from './Overview.module.css'

type OverviewProps = {
  credit: number
  seats: number
  billingPeriod: string
  monthlyPrice: number
  yearlyPrice: number
}

const CTA = ({payAmount}: {payAmount: string}) => {
  return (
    <>
      <Button variant="primary" className={styles.Button}>
        Pay {payAmount}
      </Button>
      <div className={styles.Box}>
        By clicking pay you agree to our{' '}
        <Link
          href="https://docs.github.com/en/site-policy/github-terms/github-terms-of-service"
          inline
          className={styles.Link}
        >
          Terms of Service
        </Link>{' '}
        and{' '}
        <Link
          href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
          inline
          className={styles.Link}
        >
          Privacy
        </Link>
        .
      </div>
    </>
  )
}

function Overview({credit, seats, billingPeriod, monthlyPrice, yearlyPrice}: OverviewProps) {
  const formatter = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  })

  const safeSeats = seats > 0 ? seats : 1
  const totalCycle = billingPeriod === 'monthly' ? monthlyPrice : yearlyPrice
  const totalWithSeats = totalCycle * safeSeats * (billingPeriod === 'monthly' ? 1 : 12)
  const final = totalWithSeats - credit

  const payAmount = formatter.format(Math.max(final, 0))

  return (
    <section aria-labelledby="overview-heading" className={styles.Box_1}>
      <div className={styles.Box_2}>
        <Heading id="overview-heading" as="h2" className={styles.Heading}>
          New plan
        </Heading>
      </div>
      <div className={styles.Box_3}>
        <h2 className={styles.Text}>New plan</h2>
        <span className={styles.Text_1}>
          {formatter.format(totalWithSeats)}{' '}
          <span className={styles.Text_2}>/ {billingPeriod === 'monthly' ? 'month' : 'year'}</span>
        </span>
        <div className={styles.Box_4}>
          <div>
            {safeSeats} {safeSeats > 1 ? 'seats' : 'seat'}{' '}
            <div className={styles.Box_5}>({formatter.format(totalCycle)}/month)</div>
          </div>{' '}
          <span className={styles.Text_3}>{formatter.format(totalCycle)}/month</span>
          <div>
            Unused time on old plan <div className={styles.Box_6}>(-{formatter.format(credit)})</div>
          </div>
          <span className={styles.Text_3}>-{formatter.format(credit)}</span>
        </div>
        <div className={styles.Box_7}>
          <CTA payAmount={payAmount} />
        </div>
      </div>
      <div className={styles.Box_8}>
        <CTA payAmount={payAmount} />
      </div>
    </section>
  )
}

export default Overview
