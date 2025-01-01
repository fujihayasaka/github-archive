import {IconButton} from '@primer/react'
import {XIcon} from '@primer/octicons-react'
import {LoopsActionMenu} from './controls/LoopsActionMenu'
import {HeaderActions} from './controls/HeaderActions'
import {Link, useNavigate} from 'react-router-dom'
import styles from './Header.module.css'
import {LOOPS_PATH} from '../utils/constants'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useDuplicateLoop} from '../hooks/use-duplicate-loop'
import {createShareUrl} from '../utils/share'
import {useLoopDraftStatus} from '../hooks/use-loop-draft-status'
import {UnsavedChangesButton} from './controls/UnsavedChangesButton'
import {useState} from 'react'
import {CancelLoopCreationDialog} from './CancelLoopCreationDialog'
import {useLoop} from '../hooks/queries/use-loop'

export function Header() {
  const {data: loop} = useLoop()
  const loopTitle = loop?.title
  const navigate = useNavigate()
  const duplicateLoop = useDuplicateLoop()
  const {hasChanges, isNew} = useLoopDraftStatus()
  const [showCancelDialog, setShowCancelDialog] = useState(false)

  const closeWorkbench = (event: React.MouseEvent) => {
    // If this is a new loop, show confirmation dialog
    if (isNew) {
      event.preventDefault()
      setShowCancelDialog(true)
      return
    }

    sendEvent('dotcom_chat.activate', {target: 'HEADER_WORKBENCH_CLOSE', mode: 'loops'})
  }

  const handleDeleteLoop = () => {
    navigate(LOOPS_PATH)
  }

  const copyLoopToClipboard = () => {
    if (!loop) return

    const fieldsToCopy = {
      title: loop.title,
      description: loop.description,
      nodes: loop.nodes,
    }

    const pipelineJson = JSON.stringify(fieldsToCopy, null, 2)
    navigator.clipboard.writeText(pipelineJson)
    sendEvent('dotcom_chat.activate', {target: 'HEADER_JSON_COPY', mode: 'loops'})
  }

  const shareLoop = () => {
    if (!loop) return

    const shareUrl = createShareUrl(loop)

    navigator.clipboard.writeText(shareUrl)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_SHARE', mode: 'loops'})
  }

  return (
    <div className={styles.container}>
      <div className={styles.left}>
        <IconButton
          aria-label="Close workbench"
          as={Link}
          icon={XIcon}
          onClick={closeWorkbench}
          to={LOOPS_PATH}
          variant="invisible"
        />
        <div className={styles.title}>{loopTitle}</div>
      </div>
      <div className={styles.right}>
        {hasChanges && <UnsavedChangesButton />}
        <LoopsActionMenu
          onDelete={handleDeleteLoop}
          onCopyLoop={copyLoopToClipboard}
          onDuplicate={duplicateLoop}
          loopId={loop?.id}
          variant="invisible"
          onShare={shareLoop}
        />
        <HeaderActions />
      </div>
      <CancelLoopCreationDialog isOpen={showCancelDialog} onClose={() => setShowCancelDialog(false)} />
    </div>
  )
}
