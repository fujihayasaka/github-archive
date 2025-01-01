import {CustomCopilotForm} from '../components/CustomCopilotForm'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CustomCopilot} from '../types'
import type {CopilotChatOrg} from '@github-ui/copilot-chat/utils/copilot-chat-types'

interface EditCustomCopilotPayload {
  customCopilot: CustomCopilot
  findFileWorkerPath: string
  ssoOrganizations: CopilotChatOrg[]
}

export function EditCustomCopilot() {
  const {customCopilot, findFileWorkerPath, ssoOrganizations} = useRoutePayload<EditCustomCopilotPayload>()
  return (
    <CustomCopilotForm
      customCopilot={customCopilot}
      findFileWorkerPath={findFileWorkerPath}
      ssoOrganizations={ssoOrganizations}
    />
  )
}
