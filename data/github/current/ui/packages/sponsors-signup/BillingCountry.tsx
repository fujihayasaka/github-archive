import {testIdProps} from '@github-ui/test-id-props'
import {FormControl, Select} from '@primer/react'
import type {Countries} from './BankPayout'

import styles from './BillingCountry.module.css'

export interface BillingCountryProps {
  countries: Countries
  currentBillingCountry: string | null
}

export function BillingCountry({countries, currentBillingCountry}: BillingCountryProps) {
  return (
    <FormControl className={styles.FormControl}>
      <FormControl.Label>Bank account country or region</FormControl.Label>
      <Select
        name="sponsors_listing[billing_country]"
        defaultValue={currentBillingCountry || ''}
        className={styles.Select}
        {...testIdProps('banking-country')}
      >
        {Object.entries(countries).map(([key, country]) => (
          <Select.Option key={key} value={country.countryCode} readOnly>
            {country.name}
          </Select.Option>
        ))}
      </Select>
    </FormControl>
  )
}
