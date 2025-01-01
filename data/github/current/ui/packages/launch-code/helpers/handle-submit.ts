import {verifiedFetch} from '@github-ui/verified-fetch'
import {urlEncodedRequestBody, type HiddenFieldsParams} from './url-encoded-request-body'

interface HandleSubmitParams {
  hiddenFieldsParams: HiddenFieldsParams
  inputRefs: React.MutableRefObject<HTMLInputElement[]>
  setErrorMessage: (errorMessage: string) => void
  setSubmittingForm: (submittingForm: boolean) => void
}

export const handleSubmit = async ({
  hiddenFieldsParams,
  inputRefs,
  setErrorMessage,
  setSubmittingForm,
}: HandleSubmitParams) => {
  setSubmittingForm(true)
  setErrorMessage('')
  const requestBody = urlEncodedRequestBody(hiddenFieldsParams, inputRefs)

  try {
    const result = await verifiedFetch('/account_verifications', {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      method: 'POST',
      body: requestBody,
    })

    if (result.redirected) {
      // The rails endpoint returns a 302 redirect but does not update the React partial.
      // We need to do this update manually to get the user to the correct page returned by Rails.
      window.location.href = result.url
    } else {
      setErrorMessage('Invalid launch code.')
    }
    // TODO: Log error
    // eslint-disable-next-line unused-imports/no-unused-vars
  } catch (err) {
    setErrorMessage('Request failed, please try again.')
  } finally {
    setSubmittingForm(false)
  }
}
