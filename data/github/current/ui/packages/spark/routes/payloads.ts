import type {
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatRepo,
  Docset,
  Icebreakers as ImportedIcebreakers,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export interface SparkPayload extends CopilotChatPayload {
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
}

export interface SparkHyperspacePayload extends CopilotChatPayload {
  spark: {
    icebreakers: ImportedIcebreakers
  }
}
