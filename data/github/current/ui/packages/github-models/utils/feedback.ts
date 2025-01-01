import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {Model} from '@github-ui/marketplace-common'
import type {FeedbackState} from '../routes/playground/components/GettingStartedDialog/types'
import {ModelUrlHelper} from './model-url-helper'

export async function sendFeedback({model, feedback}: {model: Model; feedback: FeedbackState}): Promise<Response> {
  const response = await verifiedFetchJSON(ModelUrlHelper.feedbackUrl(model), {
    method: 'POST',
    body: {
      feedback,
    },
  })
  if (response.ok) {
    return response
  } else {
    throw new Error('Failed to submit feedback')
  }
}
