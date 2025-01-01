import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {modelFeedbackPath, type ModelUrlable} from '@github-ui/paths'
import type {FeedbackState} from '../routes/playground/components/GettingStartedDialog/types'

export async function sendFeedback({
  model,
  feedback,
}: {
  model: ModelUrlable
  feedback: FeedbackState
}): Promise<Response> {
  const response = await verifiedFetchJSON(modelFeedbackPath(model), {
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
