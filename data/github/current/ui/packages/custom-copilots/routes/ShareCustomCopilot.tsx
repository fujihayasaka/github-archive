import {CustomCopilotForm} from '../components/CustomCopilotForm'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CustomCopilot} from '../types'
import type {CopilotChatOrg} from '@github-ui/copilot-chat/utils/copilot-chat-types'

interface ShareCustomCopilotPayload {
  customCopilot: CustomCopilot
  findFileWorkerPath: string
  ssoOrganizations: CopilotChatOrg[]
}

export function ShareCustomCopilot() {
  const {customCopilot, findFileWorkerPath, ssoOrganizations} = useRoutePayload<ShareCustomCopilotPayload>()

  return (
    <CustomCopilotForm
      findFileWorkerPath={findFileWorkerPath}
      customCopilot={customCopilot}
      ssoOrganizations={ssoOrganizations}
    />
  )
}
