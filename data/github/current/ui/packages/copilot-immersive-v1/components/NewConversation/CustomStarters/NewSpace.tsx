import {COPILOT_SPACES_NEW_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useNavigate} from 'react-router-dom'

import styles from '../NewConversation.module.css'
import {StarterPill} from '../StarterPill'

export function NewSpace() {
  const navigate = useNavigate()

  const handleCreateSpace = () => {
    navigate(COPILOT_SPACES_NEW_PATH)
    sendEvent('dotcom_chat.activate', {
      target: 'STARTER_CUSTOM_CREATE_SPACE',
      mode: 'immersive',
    })
  }

  return (
    <li className={styles.item}>
      <StarterPill name="Create space" icon="spaces" color="var(--fgColor-muted)" onClick={handleCreateSpace} />
    </li>
  )
}
