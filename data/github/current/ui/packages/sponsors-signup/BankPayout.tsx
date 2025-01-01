import {useState} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {InfoIcon} from '@primer/octicons-react'
import {Flash, FormControl, Link, Radio, Select} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import styles from './BankPayout.module.css'

export interface BankPayoutProps {
  bankPayout: boolean
  currentBillingCountry: string
  countries: Countries
  fiscalHostDocsURL: string
}

export interface Countries {
  [countryCode: string]: {
    countryCode: string
    stripeSupported: boolean
    name: string
  }
}

export function BankPayout({bankPayout, currentBillingCountry, countries, fiscalHostDocsURL}: BankPayoutProps) {
  const [bankCountryCode, setBankCountryCode] = useState(currentBillingCountry)

  const validStripeCountryCode = (countryCode: string) =>
    countryCode === '' || !!countries[countryCode]?.stripeSupported

  return (
    <>
      <div className={styles.Box}>
        <FormControl>
          <Radio value="bank" aria-describedby="bank-description" />
          <FormControl.Label className={styles.FormControl_Label}>Bank account</FormControl.Label>
        </FormControl>
        <span id="bank-description" className="note">
          Use a bank account to receive your sponsorships. Note: If you use a personal bank account, your country may
          tax your GitHub Sponsors payouts as personal income.
        </span>
      </div>
      {bankPayout && (
        <>
          <FormControl className={styles.Box}>
            <FormControl.Label>Country or region where your bank account is located</FormControl.Label>
            <Select
              name="sponsors_listing[billing_country]"
              onChange={event => {
                setBankCountryCode(event.target.value)
              }}
              className={styles.Select}
              {...testIdProps('residence-country')}
            >
              <Select.Option value="">Select a country or region</Select.Option>
              {Object.entries(countries).map(([key, country]) => (
                <Select.Option key={key} value={country.countryCode}>
                  {country.name}
                </Select.Option>
              ))}
            </Select>
          </FormControl>
          {validStripeCountryCode(bankCountryCode) || (
            <Flash className={styles.Flash} {...testIdProps('payout-invalid-bank-country')}>
              <Octicon icon={InfoIcon} />
              Your region is not supported. You can use an account with a{' '}
              <Link href={fiscalHostDocsURL} inline>
                fiscal host
              </Link>{' '}
              or sign up to be notified when Sponsors supports your region.
            </Flash>
          )}
        </>
      )}
    </>
  )
}
