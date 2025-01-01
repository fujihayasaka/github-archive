import {Box, FormControl, Select, Stack, TextInput} from '@primer/react-brand'
import {useState, useMemo, useRef} from 'react'

import {getCountryCallingCode, parsePhoneNumberFromString, getCountries} from 'libphonenumber-js'
import type {CountryCode} from 'libphonenumber-js'
import type {Country} from '../../../forms/Form/components/ConsentExperience/types'

export type PhoneInputProps = {
  id: string
  validationErrorId: string
  label: string
  error?: string
  required?: boolean
  placeholder?: string
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  name?: string
  allowedCountries?: Country[]
}

export const PhoneInput = (props: PhoneInputProps) => {
  const {id, label, error, required, placeholder, validationErrorId, onChange, allowedCountries} = props
  // Only allow countries present in both marketingTargetedCountries and libphonenumber-js
  const allowedCountryCodes = useMemo<Set<string>>(() => new Set(getCountries()), [])
  const filteredCountries = useMemo(
    () =>
      allowedCountries && allowedCountries.length > 0
        ? allowedCountries.filter(c => allowedCountryCodes.has(c.alpha))
        : getCountries().map(alpha => ({name: alpha, alpha}) as Country),
    [allowedCountries, allowedCountryCodes],
  )
  const [country, setCountry] = useState<CountryCode>('US')
  const [phoneNumber, setPhoneNumber] = useState('')
  const ref = useRef<HTMLInputElement>(null)

  const updateHiddenInput = (value: string) => {
    if (ref.current) {
      const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set

      valueSetter?.call(ref.current, value)

      ref.current.dispatchEvent(new Event('input', {bubbles: true}))
    }
  }

  const handleCountryChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const newCountry = e.target.value as CountryCode
    setCountry(newCountry)
    setPhoneNumber('')
    updateHiddenInput('')
  }

  const handlePhoneNumberChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const rawInput = e.target.value
    setPhoneNumber(rawInput)
    if (e.target.value.trim() === '') {
      updateHiddenInput('')
      return
    }
    const raw = rawInput.replace(/\D/g, '')
    const fullNumber = `+${getCountryCallingCode(country)}${raw}`
    const parsed = parsePhoneNumberFromString(raw, country)
    // Always prefer the parsed E.164 format if valid, otherwise fallback to the fullNumber
    const formattedPhone = parsed && parsed.isPossible() ? parsed.format('E.164') : fullNumber
    updateHiddenInput(formattedPhone)
  }

  return (
    <FormControl
      key={id}
      id={id}
      fullWidth
      required={required}
      validationStatus={typeof error === 'string' ? 'error' : undefined}
    >
      <FormControl.Label>{label}</FormControl.Label>
      <Stack direction="horizontal" alignItems="flex-start" padding="none" style={{width: '100%'}}>
        <Box style={{flex: 4.5, minWidth: 0}}>
          <Select value={country} onChange={handleCountryChange} aria-label="Select country for phone number">
            {filteredCountries.map(c => (
              <Select.Option key={c.alpha} value={c.alpha}>
                {c.name} ({`+${getCountryCallingCode(c.alpha as CountryCode)}`})
              </Select.Option>
            ))}
          </Select>
        </Box>
        <Box style={{flex: 5.5, minWidth: 0}}>
          <TextInput
            id={id}
            value={phoneNumber}
            onChange={handlePhoneNumberChange}
            aria-describedby={validationErrorId}
            aria-label={label}
            placeholder={placeholder}
            type="tel"
            fullWidth
            validationStatus={
              typeof phoneNumber === 'string' && phoneNumber.trim() === ''
                ? undefined
                : typeof error === 'string'
                  ? 'error'
                  : undefined
            }
            leadingText={`+${getCountryCallingCode(country)}`}
          />
        </Box>
      </Stack>
      <input name={props.name} style={{display: 'none'}} onChange={onChange} ref={ref} />
      {typeof error === 'string' ? (
        <FormControl.Validation id={validationErrorId}>{error}</FormControl.Validation>
      ) : null}
    </FormControl>
  )
}
