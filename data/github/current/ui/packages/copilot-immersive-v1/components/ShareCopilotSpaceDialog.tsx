import {COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copyText} from '@github-ui/copy-to-clipboard'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {CheckIcon, CopyIcon, InfoIcon} from '@primer/octicons-react'
import {Button, Dialog, Stack, TextInput} from '@primer/react'
import {useState} from 'react'

import styles from './ShareConversationDialog.module.css'

interface ShareCopilotSpaceDialogProps {
  closeDialog: () => void
  customCopilotId: number | string
}

export function ShareCopilotSpaceDialog({closeDialog, customCopilotId}: ShareCopilotSpaceDialogProps) {
  const [copied, setCopied] = useState(false)

  const origin = ssrSafeLocation.origin
  const sharedLink = customCopilotId ? `${origin}${COPILOT_SPACES_PATH}/${customCopilotId}/share` : `${origin}/copilot`

  const copySharedLink = () => {
    void copyText(sharedLink)
    setCopied(true)
  }

  return (
    <Dialog title="Share space" onClose={closeDialog} width="large">
      <Stack gap="condensed">
        <Stack direction="horizontal" gap="condensed" align="start">
          <InfoIcon size={20} className={styles.infoIcon} /> This space may contain private content. Viewers must have
          have access to all referenced content.
        </Stack>
        <Stack direction="horizontal" gap="condensed" align="start">
          <TextInput className="flex-1" readOnly value={sharedLink} placeholder={sharedLink} />
          {copied ? (
            <Button sx={{color: 'var(--fgColor-success)'}}>
              <CheckIcon /> Copied!
            </Button>
          ) : (
            <Button leadingVisual={CopyIcon} onClick={copySharedLink}>
              Copy link
            </Button>
          )}
        </Stack>
      </Stack>
    </Dialog>
  )
}
