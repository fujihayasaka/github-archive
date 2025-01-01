import {FormControl, Select} from '@primer/react-brand'
import {z} from 'zod'

import {useContext} from 'react'
import {FormContext} from '../../../FormContext'

import type {Country} from '../ConsentExperienceContext'

const validations = [
  {
    schema: z.string().min(1),
    message: 'Please select your country',
  },
]

export const CountrySelectField = ({countries}: {countries: Country[]}) => {
  const validationErrorId = 'country-validation-msg'
  const formContext = useContext(FormContext)
  const countryError = formContext?.errors['country']

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
        aria-describedby={validationErrorId}
      >
        <Select.Option value="">Choose your country</Select.Option>

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
