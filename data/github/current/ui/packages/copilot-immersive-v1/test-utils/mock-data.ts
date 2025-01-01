import type {Icebreaker} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'

import type {CopilotImmersivePayload} from '../routes/payloads'

export function getCopilotImmersiveAppPayload(): CopilotImmersivePayload {
  const icebreakers: Icebreaker[] = []
  for (let i = 0; i < 10; i++) {
    icebreakers.push({
      id: i.toString(),
      titleHtml: 'Testing is for cool kids',
      icon: 'light-bulb',
      color: 'var(--display-green-fgColor)',
      message: 'Testing',
    })
  }

  const icebreakersObject = {
    instructional: icebreakers,
    functional: icebreakers,
    interactional: icebreakers,
  }

  return {
    copilotChatSettingEnabled: true,
    currentUserLogin: 'monalisa',
    apiURL: 'github-copilot/chat',
    searchWorkerFilePath: '@/find-file-worker.js',
    ssoOrganizations: [],
    agentsPath: '/agents',
    optedInToPreviewFeatures: true,
    optedInToUserFeedback: true,
    reviewLab: false,
    hasCEorCBAccess: false,
    copilotUpsellBannerDismissed: false,
    customCopilotsEnabled: true,
    icebreakers: icebreakersObject,
    previewUrl: '',
    graphqlApiUrl: '',
    canShareThread: false,
    licenseType: CopilotLicenseType.LicensedFull,
  }
}
