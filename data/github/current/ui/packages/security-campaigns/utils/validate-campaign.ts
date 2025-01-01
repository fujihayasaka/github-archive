import type {FormFieldDisplayMode} from '../types/form-field-display-mode'
import type {Team} from '../types/team'
import type {User} from '../types/user'
import {assertNever} from './assert-never'
import {number as formatNumber} from '@github-ui/formatters'

export type ValidateCampaignParameters = {
  name: string
  description: string
  dueDate: Date | null
  managers: User[]
  teamManagers: Team[]
  contactLink: string | null
}

export type ValidateCampaignOptions = {
  descriptionDisplayMode: FormFieldDisplayMode
  dueDateDisplayMode: FormFieldDisplayMode
  maxManagers: number
  allowDueDateInPast: boolean
}

export type ValidateCampaignResult = {
  valid: boolean
  fieldValidationErrors: Partial<Record<keyof ValidateCampaignParameters, string>>
}

export function validateCampaign(
  {name, description, dueDate, managers, teamManagers, contactLink}: ValidateCampaignParameters,
  {descriptionDisplayMode, dueDateDisplayMode, maxManagers, allowDueDateInPast}: ValidateCampaignOptions,
): ValidateCampaignResult {
  const fieldValidationErrors: ValidateCampaignResult['fieldValidationErrors'] = {}

  if (name.length <= 0 || name.length > 50) {
    fieldValidationErrors['name'] = 'Name must be between 1 and 50 characters long'
  }

  if (!isValidForDisplayMode(descriptionDisplayMode, description.length > 0 && description.length <= 255)) {
    fieldValidationErrors['description'] = 'Description must be between 1 and 255 characters long'
  }

  if (isValidForDisplayMode(dueDateDisplayMode, dueDate !== null)) {
    if (!isValidForDisplayMode(dueDateDisplayMode, dueDate !== null && (allowDueDateInPast || dueDate > new Date()))) {
      fieldValidationErrors['dueDate'] = 'Due date must be in the future'
    }
  } else {
    fieldValidationErrors['dueDate'] = 'Due date is required'
  }

  const campaignManagersNumber = managers.length + teamManagers.length
  if (campaignManagersNumber <= 0 || campaignManagersNumber > maxManagers) {
    fieldValidationErrors['managers'] = `You must have at least one manager and at most ${formatNumber(
      maxManagers,
    )} managers`
  }

  if (contactLink && !isValidContactLink(contactLink)) {
    fieldValidationErrors['contactLink'] = 'Contact link must use http, https or mailto scheme'
  }

  return {
    valid: Object.keys(fieldValidationErrors).length === 0,
    fieldValidationErrors,
  }
}

function isValidForDisplayMode(displayMode: FormFieldDisplayMode, valid: boolean): boolean {
  switch (displayMode) {
    case 'hidden':
      return true
    case 'optional':
      return true
    case 'required':
      return valid
    default:
      assertNever(displayMode)
  }
}

/**
 * Check whether a contact link is valid utilizing URL.canParse and uses a safe scheme (http, https or mailto)
 * @param contactLink
 * @returns {boolean}
 */
export const isValidContactLink = (url: string): boolean => {
  try {
    const parsedUrl = new URL(url, undefined) // The base url needs to be passed due to linting rules
    return ['http:', 'https:', 'mailto:'].includes(parsedUrl.protocol)
  } catch {
    return false
  }
}
