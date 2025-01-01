import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpaceEditPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {copyText} from '@github-ui/copy-to-clipboard'
import {CheckIcon, CopyIcon, PencilIcon} from '@primer/octicons-react'
import {Dialog} from '@primer/react/experimental'
import {useState} from 'react'
import {useNavigate} from 'react-router-dom'

import styles from './FullInstructionsDialog.module.css'

interface FullInstructionsDialogProps {
  copilotSpace: CustomCopilot
  onClose: () => void
  returnFocusRef: React.RefObject<HTMLButtonElement>
}

const SuccessCheckIcon = (props: React.ComponentProps<typeof CheckIcon>) => (
  <CheckIcon {...props} className="fgColor-success" />
)

export function FullInstructionsDialog({copilotSpace, onClose, returnFocusRef}: FullInstructionsDialogProps) {
  const [copied, setCopied] = useState(false)

  function handleCopy() {
    void copyText(copilotSpace.generalInstructions || '')
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const navigate = useNavigate()

  return (
    <Dialog
      title="Instructions"
      onClose={onClose}
      returnFocusRef={returnFocusRef}
      position={{narrow: 'fullscreen'}}
      footerButtons={[
        {
          content: copied ? 'Copied' : 'Copy',
          leadingVisual: copied ? SuccessCheckIcon : CopyIcon,
          onClick: handleCopy,
        },
        ...(copilotSpace.editable === true
          ? [
              {
                content: 'Edit',
                leadingVisual: PencilIcon,
                onClick: () => navigate(`${getCopilotSpaceEditPath(copilotSpace)}#instructions`),
              },
            ]
          : []),
      ]}
      renderBody={() => (
        <div className="p-3">
          <p className={styles.instructionsText}>{copilotSpace.generalInstructions}</p>
        </div>
      )}
    />
  )
}
