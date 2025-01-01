import {testIdProps} from '@github-ui/test-id-props'
import {FormControl, Select} from '@primer/react'
import type {Countries} from './BankPayout'

import styles from './UserResidenceCountry.module.css'

export interface UserResidenceCountryProps {
  countries: Countries
  currentCountryOfResidence?: string
}

export function UserResidenceCountry({countries, currentCountryOfResidence}: UserResidenceCountryProps) {
  return (
    <FormControl className={styles.FormControl}>
      <FormControl.Label>Country or region of residence</FormControl.Label>
      <Select
        name="sponsors_listing[country_of_residence]"
        defaultValue={currentCountryOfResidence || ''}
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
  )
}
