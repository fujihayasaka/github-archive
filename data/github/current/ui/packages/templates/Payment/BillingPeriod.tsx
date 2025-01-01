import {Radio, Label, Heading} from '@primer/react'

import styles from './BillingPeriod.module.css'

type BillingPeriodProps = {
  billingPeriod: string
  setBillingPeriod: (billingPeriod: string) => void
  monthlyPrice: number
  yearlyPrice: number
}

function BillingPeriod({billingPeriod, setBillingPeriod, monthlyPrice, yearlyPrice}: BillingPeriodProps) {
  const formatter = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  })

  return (
    <div className={styles.Box}>
      <Heading as="h2" className={styles.Heading}>
        Billing period
      </Heading>
      <div className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <Radio
              aria-describedby="price-yearly"
              name="cycle"
              value="yearly"
              id="yearly"
              onChange={() => setBillingPeriod('yearly')}
              checked={billingPeriod === 'yearly'}
            />
            <div className={styles.Box_4}>
              <label htmlFor="yearly" className={styles.Box_5}>
                Pay yearly{' '}
                <Label variant="accent" className={styles.Label}>
                  2 months free
                </Label>
              </label>
              <span id="price-yearly" className={styles.Text}>
                {formatter.format(yearlyPrice)} per seat / month
              </span>
            </div>
          </div>
          <div className={styles.Box_6}>
            <div>
              <Radio
                aria-describedby="price-monthly"
                name="cycle"
                value="monthly"
                id="monthly"
                onChange={() => setBillingPeriod('monthly')}
                checked={billingPeriod === 'monthly'}
              />
            </div>
            <div className={styles.Box_4}>
              <label htmlFor="monthly" className={styles.Box_5}>
                Pay monthly{' '}
              </label>
              <span id="price-monthly" className={styles.Text}>
                {formatter.format(monthlyPrice)} per seat / month
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default BillingPeriod
