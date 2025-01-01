// eslint-disable-next-line no-restricted-imports
import {Button, Avatar, Heading} from '@primer/react'

import styles from './BillingInformation.module.css'

function BillingInformation() {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          Billing information
        </Heading>
        <Button size="small" aria-label="Edit billing information">
          Edit
        </Button>
      </div>
      <div className={styles.Box_2}>
        <div className={styles.Box_3}>
          <div className={styles.Box_4}>
            <Avatar size={40} src="https://avatars.githubusercontent.com/u/92997159?v=4" className={styles.Avatar_0} />
            <div className={styles.Box_5}>
              <span className={styles.Text}>Mona</span>
              <span className={styles.Text_1}>Personal account</span>
            </div>
          </div>
          <div className={styles.Box_6}>
            <span className={styles.Text}>Playground Inc.</span>
            <span className={styles.Text_1}>88 Colin P Kelly Jr Way</span>
            <span className={styles.Text_1}>San Francisco, CA 94117</span>
            <span className={styles.Text_1}>United States of America</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default BillingInformation
