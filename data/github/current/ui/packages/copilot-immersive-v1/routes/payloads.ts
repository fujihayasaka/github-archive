import type {
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatReference,
  CopilotChatRepo,
  Docset,
  Icebreaker as ImportedIcebreaker,
  Icebreakers as ImportedIcebreakers,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export type Icebreaker = ImportedIcebreaker
export type Icebreakers = ImportedIcebreakers

export interface CopilotImmersivePayload extends CopilotChatPayload {
  copilotChatSettingEnabled: boolean
  searchWorkerFilePath: string
  requestedTopic?: CopilotChatRepo | Docset
  ssoOrganizations: CopilotChatOrg[]
  copilotUpsellBannerDismissed: boolean
  icebreakers: ImportedIcebreakers
  graphqlApiUrl: string
  previewUrl: string
  canShareThread: boolean
  realIp?: string
  helpUrl?: string
  figmaAuthUrl?: string
  reference?: CopilotChatReference
}
