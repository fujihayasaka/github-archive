import {createContext, useContext} from 'react'
import type {Team} from '../types/team'
import type {FormFieldDisplayMode} from '../types/form-field-display-mode'
import type {ValidateCampaignResult} from '../utils/validate-campaign'
import type {User} from '../types/user'

// To ensure that we can compose different components to create different form layouts depending on where the form
// is shown, we use a context to pass the form state and handlers down to the components that need them.
// Use SecurityCampaignFormWrapper as the top-level component to provide the context.
export type SecurityCampaignFormContextValue = {
  allowDueDateInPast: boolean

  campaignName: string
  setCampaignName: (name: string) => void
  campaignDescription: string
  setCampaignDescription: (description: string) => void
  campaignDueDate: Date | null
  setCampaignDueDate: (date: Date | null) => void
  campaignManagers: User[]
  setCampaignManagers: (managers: User[]) => void
  campaignTeamManagers: Team[]
  setCampaignTeamManagers: (teamManagers: Team[]) => void
  campaignContactLink: string | null
  setCampaignContactLink: (contactLink: string | null) => void
  campaignGenerateAutofixPullRequests: boolean
  setCampaignGenerateAutofixPullRequests: (generate: boolean) => void
  campaignGenerateIssues: boolean
  setCampaignGenerateIssues: (generate: boolean) => void

  validationError: ValidateCampaignResult

  handleSubmit: () => void
  isPending: boolean
  formError: Error | null

  resetForm: () => void

  descriptionDisplayMode: FormFieldDisplayMode
  dueDateDisplayMode: FormFieldDisplayMode
}

export const SecurityCampaignFormContext = createContext<SecurityCampaignFormContextValue | null>(null)

export function useSecurityCampaignFormContext(): SecurityCampaignFormContextValue {
  const context = useContext(SecurityCampaignFormContext)
  if (context === null) {
    throw new Error('SecurityCampaignFormContext must be used within a SecurityCampaignFormContextProvider')
  }

  return context
}
