import {FormControl, Select} from '@primer/react-brand'
import {z} from 'zod/v4'

import {useCallback, useContext} from 'react'
import {FormContext} from '../../../FormContext'

import {getAnalyticsEvent} from '../../../../../../lib/utils/analytics'
import type {Country} from '../types'

const validations = [
  {
    schema: z.string().min(1),
    message: 'Please select your country/region',
  },
]

export type CountrySelectFieldProps = {
  countries: Country[]
  onChange?: (country: Country) => void
}

export const CountrySelectField = ({countries, onChange}: CountrySelectFieldProps) => {
  const validationErrorId = 'country-validation-msg'
  const formContext = useContext(FormContext)
  const countryError = formContext?.errors['country']

  const handleCountryChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      const selectedCountry = e.target.value
      if (selectedCountry) {
        const country = countries.find(c => c.alpha === selectedCountry)
        if (country) {
          onChange?.(country)
        }
      }
    },
    [countries, onChange],
  )

  return (
    <FormControl
      id="form-field-country"
      validationStatus={typeof countryError === 'string' ? 'error' : undefined}
      fullWidth
      required
    >
      <FormControl.Label>{'Country'}</FormControl.Label>

      <Select
        {...formContext?.register('country', {
          label: 'Country',
          required: true,
          validations,
        })}
        {...getAnalyticsEvent({
          action: 'country',
          tag: 'select',
          context: 'form_control',
          location: 'form',
        })}
        aria-describedby={validationErrorId}
        onChange={handleCountryChange}
      >
        <Select.Option value="">Choose your country/region</Select.Option>

        {countries.map(country => (
          <Select.Option key={country.name} value={country.alpha}>
            {country.name}
          </Select.Option>
        ))}
      </Select>

      {typeof countryError === 'string' ? (
        <FormControl.Validation id={validationErrorId}>{countryError}</FormControl.Validation>
      ) : null}
    </FormControl>
  )
}
