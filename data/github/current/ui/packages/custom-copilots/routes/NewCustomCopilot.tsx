import {CustomCopilotForm} from '../components/CustomCopilotForm'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CopilotChatOrg} from '@github-ui/copilot-chat/utils/copilot-chat-types'

interface NewCustomCopilotPayload {
  findFileWorkerPath: string
  ssoOrganizations: CopilotChatOrg[]
}

export function NewCustomCopilot() {
  const {findFileWorkerPath, ssoOrganizations} = useRoutePayload<NewCustomCopilotPayload>()
  return <CustomCopilotForm findFileWorkerPath={findFileWorkerPath} ssoOrganizations={ssoOrganizations} />
}
