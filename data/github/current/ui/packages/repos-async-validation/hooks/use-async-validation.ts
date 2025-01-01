import {verifiedFetchJSON, type JSONRequestInit} from '@github-ui/verified-fetch'
import {useState} from 'react'

type VALIDATION_RESULT = 'INVALID' | 'VALID' | 'UNKNOWN'

export function useAsyncValidation(baseValidationUrl: string, type: string) {
  const [validityResult, setValidityResult] = useState<VALIDATION_RESULT>('UNKNOWN')

  const isValid = validityResult === 'VALID'
  const showError = validityResult === 'INVALID'

  const validate = async (value: object, header: JSONRequestInit = {}): Promise<boolean> => {
    setValidityResult('UNKNOWN')

    if (!type) {
      return true
    }

    const result = await requestServerResult(value, `${baseValidationUrl}/${type}`, header)
    setValidityResult(result)
    return resultValidity(result)
  }

  const reset = (forceValid = false) => {
    setValidityResult(forceValid ? 'VALID' : 'UNKNOWN')
  }

  return {
    isValid,
    showError,
    validate,
    reset,
  }
}

const requestServerResult = async (body: object, url: string, header?: JSONRequestInit): Promise<VALIDATION_RESULT> => {
  const response = await verifiedFetchJSON(url, {
    ...header,
    method: 'POST',
    body,
  })

  if (response.ok) {
    const {valid} = await response.json()
    return valid ? 'VALID' : 'INVALID'
  } else if (response.status === 400) {
    return 'INVALID'
  } else {
    return 'UNKNOWN'
  }
}

const resultValidity = (result: VALIDATION_RESULT) => {
  switch (result) {
    case 'VALID':
    case 'UNKNOWN':
      return true
    case 'INVALID':
      return false
  }
}

export const requestServerValidation = async (body: object, url: string): Promise<boolean> =>
  resultValidity(await requestServerResult(body, url))
