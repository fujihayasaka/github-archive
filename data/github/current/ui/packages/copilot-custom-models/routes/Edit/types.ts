import type {Language} from '../../types'

export interface RoutePayload {
  availableLanguages: Language[]
  canCollectPrivateTelemetry: boolean
  createPath: string
  languages: string[]
  organization: string
  pipelineId: string
  policyPath: string
  repoCount: number
  repoListPath: string
  showPath: string
  wasPrivateTelemetryCollected: boolean
}
