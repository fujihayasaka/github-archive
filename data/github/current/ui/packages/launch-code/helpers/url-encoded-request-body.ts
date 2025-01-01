import type {MutableRefObject} from 'react'

export interface HiddenFieldsParams {
  return_to: string
  invitation_token: string
  repo_invitation_token: string
  plan: string
  verification: string
  setup_organization: string
  trial_acquisition_channel: string
}

export const urlEncodedRequestBody = (
  hiddenFieldsParams: HiddenFieldsParams,
  inputRefs: MutableRefObject<HTMLInputElement[]>,
): string => {
  const urlEncodedData = new URLSearchParams()

  urlEncodedData.append('return_to', hiddenFieldsParams?.return_to ?? '')
  urlEncodedData.append('invitation_token', hiddenFieldsParams?.invitation_token ?? '')
  urlEncodedData.append('repo_invitation_token', hiddenFieldsParams?.repo_invitation_token ?? '')
  urlEncodedData.append('plan', hiddenFieldsParams?.plan ?? '')
  urlEncodedData.append('verification', hiddenFieldsParams?.verification ?? '')
  urlEncodedData.append('setup_organization', hiddenFieldsParams?.setup_organization ?? '')
  urlEncodedData.append('trial_acquisition_channel', hiddenFieldsParams?.trial_acquisition_channel ?? '')

  const launchCode = inputRefs.current.map(input => input.value)
  for (const code of launchCode) {
    urlEncodedData.append('launch_code[]', code)
  }
  return urlEncodedData.toString()
}
