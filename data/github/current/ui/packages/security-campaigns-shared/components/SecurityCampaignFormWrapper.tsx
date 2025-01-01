import {useCallback, useEffect, useMemo, useRef, useState, type ReactNode} from 'react'
import type {User} from '../types/user'
import type {SecurityCampaignForm} from '../types/security-campaign'
import {SecurityCampaignFormContext, type SecurityCampaignFormContextValue} from './SecurityCampaignFormContext'
import type {Team} from '../types/team'
import type {FormFieldDisplayMode} from '../types/form-field-display-mode'
import {validateCampaign} from '../utils/validate-campaign'
import type {CampaignInitialValues} from '../types/campaign-initial-values'

export type SecurityCampaignFormWrapperProps = {
  initialValues: CampaignInitialValues | undefined
  currentUser: User | undefined
  allowDueDateInPast: boolean
  maxManagers: number

  submitForm: (campaign: SecurityCampaignForm) => void
  reset: () => void
  isPending: boolean
  formError: Error | null

  descriptionDisplayMode?: FormFieldDisplayMode
  dueDateDisplayMode?: FormFieldDisplayMode

  children: ReactNode
}

export function SecurityCampaignFormWrapper({
  initialValues,
  currentUser,
  allowDueDateInPast,
  maxManagers,
  submitForm,
  reset,
  isPending,
  formError,
  descriptionDisplayMode = 'required',
  dueDateDisplayMode = 'required',
  children,
}: SecurityCampaignFormWrapperProps) {
  const initialCampaignName = initialValues?.name ?? ''
  const initialCampaignDescription = initialValues?.description ?? ''
  const initialCampaignDueDate = useMemo(
    () => (initialValues?.endsAt ? new Date(initialValues.endsAt) : null),
    [initialValues],
  )
  const initialCampaignManagers = useMemo(
    () =>
      initialValues?.managers && initialValues.managers.length > 0
        ? initialValues.managers
        : currentUser
          ? [currentUser]
          : [],
    [initialValues, currentUser],
  )
  const inittialCampaignTeamManagers =
    initialValues?.teamManagers && initialValues?.teamManagers.length > 0 ? initialValues.teamManagers : []
  const initialCampaignContactLink = initialValues?.contactLink ?? null

  const [campaignName, setCampaignName] = useState(initialCampaignName)
  const [campaignDescription, setCampaignDescription] = useState(initialCampaignDescription)
  const [campaignDueDate, setCampaignDueDate] = useState<Date | null>(initialCampaignDueDate)
  const [campaignManagers, setCampaignManagers] = useState<User[]>(initialCampaignManagers)
  const [campaignTeamManagers, setCampaignTeamManagers] = useState<Team[]>(inittialCampaignTeamManagers)
  const [campaignContactLink, setCampaignContactLink] = useState<string | null>(initialCampaignContactLink)
  const [campaignGenerateAutofixPullRequests, setCampaignGenerateAutofixPullRequests] = useState(false)
  const [campaignGenerateIssues, setCampaignGenerateIssues] = useState(false)

  const [validationError, setValidationError] = useState<string | null>(null)

  useEffect(() => {
    const {valid} = validateCampaign(
      {
        name: campaignName,
        description: campaignDescription,
        dueDate: campaignDueDate,
        managers: campaignManagers,
        teamManagers: campaignTeamManagers,
      },
      {
        descriptionDisplayMode,
        dueDateDisplayMode,
        maxManagers,
        allowDueDateInPast,
      },
    )
    if (!valid) {
      setValidationError('Campaign details are invalid')
    } else {
      setValidationError(null)
    }
  }, [
    campaignName,
    campaignDescription,
    campaignDueDate,
    allowDueDateInPast,
    campaignTeamManagers,
    campaignManagers,
    maxManagers,
    descriptionDisplayMode,
    dueDateDisplayMode,
  ])

  const clearValidationError = useCallback(() => {
    setValidationError(null)
  }, [])

  // This is a performance optimization which ensures that the handleSubmit function does not change
  // on every render. This is important because the handleSubmit function is passed as a prop to
  // child components and we want to avoid unnecessary re-renders.
  const handleSubmitRef = useRef<() => void>(() => {})
  const handleSubmit = useCallback(() => {
    handleSubmitRef.current()
  }, [])
  useEffect(() => {
    handleSubmitRef.current = () => {
      if (validationError) {
        // Should not happen as validation should prevent the form from being submitted
        return
      }

      submitForm({
        name: campaignName,
        description: campaignDescription,
        endsAt: campaignDueDate?.toISOString() ?? '',
        managers: campaignManagers,
        teamManagers: campaignTeamManagers,
        contactLink: campaignContactLink,
        generateAutofixPullRequests: campaignGenerateAutofixPullRequests,
        generateIssues: campaignGenerateIssues,
      })
    }
  }, [
    validationError,
    campaignDueDate,
    campaignName,
    campaignDescription,
    campaignManagers,
    campaignTeamManagers,
    campaignContactLink,
    campaignGenerateAutofixPullRequests,
    campaignGenerateIssues,
    submitForm,
  ])

  const resetForm = useCallback(() => {
    // Reset inputs
    setCampaignName(initialCampaignName)
    setCampaignDescription(initialCampaignDescription)
    setCampaignDueDate(initialCampaignDueDate)
    setCampaignManagers(initialCampaignManagers)
    setCampaignContactLink(initialCampaignContactLink)

    // Clear errors
    setValidationError(null)
    reset()
  }, [
    initialCampaignName,
    initialCampaignDescription,
    initialCampaignDueDate,
    initialCampaignManagers,
    initialCampaignContactLink,
    reset,
  ])

  const value: SecurityCampaignFormContextValue = useMemo<SecurityCampaignFormContextValue>(
    () => ({
      allowDueDateInPast,
      campaignName,
      setCampaignName,
      campaignDescription,
      setCampaignDescription,
      campaignDueDate,
      setCampaignDueDate,
      campaignManagers,
      setCampaignManagers,
      campaignTeamManagers,
      setCampaignTeamManagers,
      campaignGenerateAutofixPullRequests,
      campaignGenerateIssues,
      campaignContactLink,
      setCampaignContactLink,
      setCampaignGenerateAutofixPullRequests,
      setCampaignGenerateIssues,
      validationError,
      clearValidationError,
      handleSubmit,
      resetForm,
      isPending,
      formError,
      descriptionDisplayMode,
      dueDateDisplayMode,
    }),
    [
      allowDueDateInPast,
      campaignName,
      campaignDescription,
      campaignDueDate,
      campaignManagers,
      campaignTeamManagers,
      campaignContactLink,
      campaignGenerateAutofixPullRequests,
      campaignGenerateIssues,
      validationError,
      clearValidationError,
      handleSubmit,
      resetForm,
      isPending,
      formError,
      descriptionDisplayMode,
      dueDateDisplayMode,
    ],
  )

  return <SecurityCampaignFormContext.Provider value={value}>{children}</SecurityCampaignFormContext.Provider>
}
