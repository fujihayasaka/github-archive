import {useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {BookIcon, CommentDiscussionIcon, GitPullRequestIcon, InfoIcon, IssueOpenedIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useRef, useState} from 'react'

import styles from './PreviewModelCapabilityWarning.module.css'

export function PreviewModelCapabilityWarning() {
  const model = useChatStateValue('model')
  const [isOpen, setOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)

  if (!model || !model.hasLimitedCapabilities) return null

  return (
    <>
      <IconButton
        className="fgColor-accent"
        variant="invisible"
        aria-label="Model capabilities"
        icon={() => <InfoIcon className="fgColor-accent" />}
        ref={buttonRef}
        onClick={() => {
          setOpen(true)
          sendEvent('dotcom_chat.activate', {target: 'PREVIEW_MODEL_INFO_OPEN', mode: 'immersive'})
        }}
      />

      {isOpen && (
        <Dialog
          title={`Limited capabilities (${model.displayName})`}
          width="large"
          onClose={() => {
            setOpen(false)
            sendEvent('dotcom_chat.activate', {target: 'PREVIEW_MODEL_INFO_CLOSE', mode: 'immersive'})
          }}
          returnFocusRef={buttonRef}
        >
          <div className={styles.content}>
            <p>
              This model has limited capabilities in retrieving external data. Learn more about selecting the right
              model{' '}
              <a
                href="https://docs.github.com/en/copilot/using-github-copilot/ai-models/choosing-the-right-ai-model-for-your-task"
                target="_blank"
                rel="noopener noreferrer"
              >
                here
              </a>
              . Here are a few of the common actions that are not supported:
            </p>

            <ul className="border rounded-2">
              <h3 className={styles.header}>Not supported</h3>
              <li className={styles.row}>
                <BookIcon className={styles.rowIcon} /> Using knowledge bases
              </li>
              <li className={styles.row}>
                <IssueOpenedIcon className={styles.rowIcon} /> Retrieving issues
              </li>
              <li className={styles.row}>
                <GitPullRequestIcon className={styles.rowIcon} /> Retrieving pull requests
              </li>
              <li className={styles.row}>
                <CommentDiscussionIcon className={styles.rowIcon} /> Retrieving discussions
              </li>
            </ul>
          </div>
        </Dialog>
      )}
    </>
  )
}
