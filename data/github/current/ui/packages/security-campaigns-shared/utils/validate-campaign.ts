import type {FormFieldDisplayMode} from '../types/form-field-display-mode'
import type {Team} from '../types/team'
import type {User} from '../types/user'
import {assertNever} from './assert-never'

export type ValidateCampaignParameters = {
  name: string
  description: string
  dueDate: Date | null
  managers: User[]
  teamManagers: Team[]
}

export type ValidateCampaignOptions = {
  descriptionDisplayMode: FormFieldDisplayMode
  dueDateDisplayMode: FormFieldDisplayMode
  maxManagers: number
  allowDueDateInPast: boolean
}

export type ValidateCampaignResult = {
  valid: boolean
  invalidFields: Array<keyof ValidateCampaignParameters>
}

export function validateCampaign(
  {
    name,
    description,

    dueDate,
    managers,
    teamManagers,
  }: ValidateCampaignParameters,
  {descriptionDisplayMode, dueDateDisplayMode, maxManagers, allowDueDateInPast}: ValidateCampaignOptions,
): ValidateCampaignResult {
  const invalidFields: ValidateCampaignResult['invalidFields'] = []

  if (name.length <= 0 || name.length > 50) {
    invalidFields.push('name')
  }

  if (!isValidForDisplayMode(descriptionDisplayMode, description.length > 0 && description.length <= 255)) {
    invalidFields.push('description')
  }

  if (isValidForDisplayMode(dueDateDisplayMode, dueDate !== null)) {
    if (!isValidForDisplayMode(dueDateDisplayMode, dueDate !== null && (allowDueDateInPast || dueDate > new Date()))) {
      invalidFields.push('dueDate')
    }
  } else {
    invalidFields.push('dueDate')
  }

  const campaignManagersNumber = managers.length + teamManagers.length
  if (campaignManagersNumber <= 0 || campaignManagersNumber > maxManagers) {
    invalidFields.push('managers')
  }

  return {
    valid: invalidFields.length === 0,
    invalidFields,
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
