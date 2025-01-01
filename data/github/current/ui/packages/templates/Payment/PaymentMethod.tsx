import {Heading, Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {CreditCardIcon} from '@primer/octicons-react'

import styles from './PaymentMethod.module.css'

function PaymentMethod() {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          Payment method
        </Heading>
        <Button size="small" aria-label="Edit payment method">
          Edit
        </Button>
      </div>
      <div className={styles.Box_2}>
        <div className={styles.Box_3}>
          <div className={styles.Box_4}>
            <div>
              <Octicon icon={CreditCardIcon} className={styles.Octicon} />
            </div>
            <div className={styles.Box_5}>
              <span className={styles.Text}>Visa ending 3425</span>
              <span className={styles.Octicon}>Expiring: March 2028</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default PaymentMethod
