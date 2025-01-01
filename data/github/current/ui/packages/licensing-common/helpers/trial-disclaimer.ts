import {format} from 'date-fns'
import type {TrialInfo} from '../types/trial-info'

export function trialDisclaimer(trialInfo?: TrialInfo) {
  if (!trialInfo) {
    return ''
  }

  return `Trial ${trialInfo.isActive ? 'ends' : 'ended'} on ${format(trialInfo.expirationDate, 'MMMM d, yyyy')}.`
}
