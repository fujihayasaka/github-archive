import {RepoAvatar} from '@github-ui/copilot-chat/components/RepoAvatar'
import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {InfoIcon} from '@primer/octicons-react'
import {Dialog, Flash, Link, Stack} from '@primer/react'
import type {RefObject} from 'react'

import styles from './IndexingConfirmationDialog.module.css'

interface IndexingConfirmationDialogProps {
  onCancel: () => void
  onConfirm: () => void
  topic: CopilotChatRepo
  remainingRepoIndexTokens: number | undefined
  returnFocusRef: RefObject<HTMLElement>
}

export function IndexingConfirmationDialog({
  onCancel,
  onConfirm,
  topic,
  remainingRepoIndexTokens,
  returnFocusRef,
}: IndexingConfirmationDialogProps) {
  const limitedTokens = remainingRepoIndexTokens !== undefined

  return (
    <Dialog
      width="large"
      title="Start indexing"
      position={{
        narrow: 'fullscreen',
        regular: 'center',
      }}
      onClose={onCancel}
      returnFocusRef={returnFocusRef}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onCancel,
        },
        {
          buttonType: 'primary',
          content: 'Start indexing',
          onClick: onConfirm,
        },
      ]}
    >
      <Stack direction="vertical" gap="normal">
        {limitedTokens && (
          <Flash className={styles.banner}>
            <Stack direction="horizontal" align="start" gap="condensed">
              <InfoIcon size={16} />
              <p className={styles.flashText}>
                Your account has {remainingRepoIndexTokens} repositories left for indexing. <br />
                <Link inline href="https://gh.io/copilot-indexing">
                  Learn more
                </Link>
              </p>
            </Stack>
          </Flash>
        )}
        <p className={styles.hint}>
          Index this repository to get better answers on code specific questions. This is optional and won&apos;t affect
          responses related to knowledge bases, pull requests, issues, discussions, or commits.
        </p>
        <Stack gap="normal" direction="horizontal" align="center" padding="normal" className={styles.repo}>
          <RepoAvatar ownerLogin={topic.ownerLogin} ownerType={topic.ownerType} size={20} />
          <span className={styles.repoLabel}>
            {topic.ownerLogin}/{topic.name}
          </span>
        </Stack>
        <p className={styles.disclaimer}>
          Initial indexing may take up to 30 minutes for large repositories. After that, re-indexing is automatic,
          faster, and typically completes within 5 minutes of each push.
        </p>
      </Stack>
    </Dialog>
  )
}
