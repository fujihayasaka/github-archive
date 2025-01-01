import {useState} from 'react'
import {PageLayout, Heading, Button} from '@primer/react'
import {ArrowLeftIcon} from '@primer/octicons-react'

import Overview from './Overview'
import Account from './Account'
import BillingPeriod from './BillingPeriod'
import Navigation from './Navigation'
import TotalSeats from './TotalSeats'
import BillingInformation from './BillingInformation'
import PaymentMethod from './PaymentMethod'

import styles from './Payment.module.css'

const YEARLY_PRICE = 19.5
const MONTHLY_PRICE = 24
const CREDIT = 223

export function Payment() {
  const [billingPeriod, setBillingPeriod] = useState('yearly')
  const [seats, setSeats] = useState(20)

  return (
    <div className={styles.Box}>
      <Navigation />
      <PageLayout containerWidth="large">
        <PageLayout.Content padding="none" className={styles.PageLayout_Content}>
          <div>
            <Button
              as="a"
              variant="invisible"
              href="https://github.com"
              leadingVisual={ArrowLeftIcon}
              sx={{
                color: 'accent.fg',
                fontSize: 1,
                fontWeight: 'semibold',
                mb: [3, 3, 5],
                marginLeft: [-3, -3, -2],
              }}
            >
              Compare plans
            </Button>
          </div>
          <div className={styles.Box_1}>
            <Heading as="h1" className={styles.Heading}>
              Subscribe to GitHub Enterprise
            </Heading>
            <Account />
            <BillingPeriod
              billingPeriod={billingPeriod}
              setBillingPeriod={setBillingPeriod}
              yearlyPrice={YEARLY_PRICE}
              monthlyPrice={MONTHLY_PRICE}
            />
            <TotalSeats seats={seats} setSeats={setSeats} />
            <BillingInformation />
            <PaymentMethod />
          </div>
        </PageLayout.Content>
        <PageLayout.Pane position="end" sticky>
          <Overview
            yearlyPrice={YEARLY_PRICE}
            monthlyPrice={MONTHLY_PRICE}
            credit={CREDIT}
            billingPeriod={billingPeriod}
            seats={seats}
          />
        </PageLayout.Pane>
      </PageLayout>
    </div>
  )
}
