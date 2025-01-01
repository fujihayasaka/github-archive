import {useMemo} from 'react'
import {Box, Checkbox, Flash, FormControl, TextInput, Textarea} from '@primer/react'
import {DatePicker} from '@github-ui/date-picker'
import {useSecurityCampaignFormContext} from './SecurityCampaignFormContext'
import {SecurityCampaignManagersSelect} from './SecurityCampaignManagersSelect'

export interface SecurityCampaignFormContentsProps {
  organizationLogin: string
  maxManagers: number
  readOnly?: boolean
  showAutofixPullRequests?: boolean
  showGenerateIssues?: boolean
}

export function SecurityCampaignFormContents({
  organizationLogin,
  maxManagers,
  readOnly = false,
  showAutofixPullRequests,
  showGenerateIssues,
}: SecurityCampaignFormContentsProps) {
  const {
    campaignName,
    setCampaignName,
    campaignDescription,
    setCampaignDescription,
    campaignManagers,
    setCampaignManagers,
    campaignTeamManagers,
    setCampaignTeamManagers,
    campaignDueDate,
    setCampaignDueDate,
    campaignContactLink,
    setCampaignContactLink,
    campaignGenerateAutofixPullRequests,
    setCampaignGenerateAutofixPullRequests,
    campaignGenerateIssues,
    setCampaignGenerateIssues,
    allowDueDateInPast,
    handleSubmit: handleFormSubmit,
    formError,
    isPending,
    descriptionDisplayMode,
    dueDateDisplayMode,
  } = useSecurityCampaignFormContext()

  const datePickerMinDate = useMemo(() => {
    if (allowDueDateInPast) {
      return undefined
    } else {
      const date = new Date()
      date.setDate(date.getDate() + 1)
      return date
    }
  }, [allowDueDateInPast])

  const handleGenerateAutofixPullRequestsChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setCampaignGenerateAutofixPullRequests(e.target.checked)
  }

  const handleGenerateIssuesChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setCampaignGenerateIssues(e.target.checked)
  }

  const handleSubmit = async (e: React.FormEvent<HTMLElement>) => {
    e.preventDefault()

    handleFormSubmit()
  }

  const disabled = isPending || readOnly

  return (
    <>
      {formError && (
        <Flash variant="danger" className="mb-2">
          {formError.message}
        </Flash>
      )}
      <form onSubmit={handleSubmit}>
        <Box sx={{pb: 3}}>
          <FormControl required disabled={disabled}>
            <FormControl.Label>Campaign name</FormControl.Label>
            <TextInput
              placeholder="A short and descriptive name for this security campaign."
              sx={{width: '100%'}}
              value={campaignName}
              maxLength={50}
              name="campaign_name"
              onChange={e => setCampaignName(e.target.value)}
            />
          </FormControl>
        </Box>
        {descriptionDisplayMode !== 'hidden' && (
          <Box sx={{pb: 3}}>
            <FormControl required={descriptionDisplayMode === 'required'} disabled={disabled}>
              <FormControl.Label>Short description</FormControl.Label>
              <Textarea
                placeholder="Let everybody know what this security campaign is about and why it's important to remediate these alerts."
                sx={{width: '100%'}}
                rows={5}
                value={campaignDescription}
                maxLength={255}
                name="campaign_description"
                onChange={e => setCampaignDescription(e.target.value)}
              />
            </FormControl>
          </Box>
        )}
        {dueDateDisplayMode !== 'hidden' && (
          <Box sx={{pb: 3}}>
            <FormControl required={dueDateDisplayMode === 'required'}>
              <FormControl.Label>Campaign due date</FormControl.Label>
              <DatePicker
                value={campaignDueDate}
                minDate={datePickerMinDate}
                onChange={d => setCampaignDueDate(d)}
                // Ensures the popup appears on screen instead of being cut off
                anchoredOverlayProps={{side: 'outside-top'}}
                disabled={disabled}
              />
              <FormControl.Caption>Date to address all campaign alerts</FormControl.Caption>
            </FormControl>
          </Box>
        )}
        <Box sx={{pb: 3}}>
          <FormControl required>
            <FormControl.Label>Campaign managers</FormControl.Label>
            <SecurityCampaignManagersSelect
              users={campaignManagers}
              onChangeUsers={setCampaignManagers}
              teams={campaignTeamManagers}
              onChangeTeams={setCampaignTeamManagers}
              organizationLogin={organizationLogin}
              maxManagers={maxManagers}
              disabled={disabled}
            />
            <FormControl.Caption>These users and teams will be the campaign contacts</FormControl.Caption>
          </FormControl>
        </Box>
        <Box sx={{pb: 3}}>
          <FormControl disabled={disabled}>
            <FormControl.Label>Contact link</FormControl.Label>
            <TextInput
              placeholder="Provide a link for contacting the campaign managers."
              sx={{width: '100%'}}
              value={campaignContactLink ?? ''}
              name="campaign_contact_link"
              onChange={e => setCampaignContactLink(e.target.value || null)} // Use || operator to send null instead of empty string
            />
          </FormControl>
        </Box>
        {showGenerateIssues && (
          <Box sx={{pb: 3}}>
            <FormControl disabled={disabled}>
              <Checkbox checked={campaignGenerateIssues} onChange={handleGenerateIssuesChange} />
              <FormControl.Label>Create repository issues for this campaign</FormControl.Label>
              <FormControl.Caption>
                Selecting this option will create a campaign issue in each repository within this campaign, except if
                issues are disabled.
              </FormControl.Caption>
            </FormControl>
          </Box>
        )}
        {showAutofixPullRequests && (
          <Box sx={{pb: 3}}>
            <FormControl disabled={disabled}>
              <Checkbox
                checked={campaignGenerateAutofixPullRequests}
                onChange={handleGenerateAutofixPullRequestsChange}
              />
              <FormControl.Label>Generate pull request using Copilot Autofix</FormControl.Label>
              <FormControl.Caption>
                Automatically generate one pull request for each repository in the campaign applying potential fixes
                generated by Copilot Autofix.
              </FormControl.Caption>
            </FormControl>
          </Box>
        )}
      </form>
    </>
  )
}
