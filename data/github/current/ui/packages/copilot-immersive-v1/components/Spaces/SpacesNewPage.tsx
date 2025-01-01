import {COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useNavigate} from '@github-ui/use-navigate'

import {SpacesForm} from './SpacesForm'

export function SpacesNewPage() {
  const navigate = useNavigate()

  function handleCancel() {
    navigate(COPILOT_SPACES_PATH)
  }

  return <SpacesForm onCancel={handleCancel} />
}
