import {LABELS} from './constants/labels'

export const formatFormErrorMessage = (errors: Error[]) => {
  const errorMessages = errors
    .map(err => err?.message)
    .filter(Boolean)
    .join(', ')

  // Some gql errors start with lowercase letters, so normalizing it
  const cleanedErrorMessages = errorMessages ? errorMessages.charAt(0).toUpperCase() + errorMessages.slice(1) : null

  return cleanedErrorMessages ?? LABELS.updateLabelError
}
