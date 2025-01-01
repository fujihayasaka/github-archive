import {sendEvent, type SendEventContext} from '@github-ui/hydro-analytics'

export function sendVisionErrorEvent(type: string, context?: SendEventContext) {
  sendEvent('dotcom_chat.vision.error', {type, ...context})
}
