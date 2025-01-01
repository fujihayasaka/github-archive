import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon} from '@primer/octicons-react'
import {Button, Flash, Heading, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useRef, useState} from 'react'

import {MemexIssueTypeRenameDialog} from '../../../components/user-notices/memex-issue-type-rename-dialog'
import type {ColumnWarningKind} from '../../../helpers/get-column-warning'
import type {ColumnModel} from '../../../models/column-model'
import {ColumnBannerResources} from '../../../strings'
import styles from './column-settings-banner.module.css'

type ColumnSettingsBannerProps = {
  column: ColumnModel
  warning: ColumnWarningKind
}

export function ColumnSettingsBanner({column, warning}: ColumnSettingsBannerProps) {
  const [isRenameDialogOpen, setIsRenameDialogOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement | null>(null)

  // Only rename banner is implemented
  if (warning !== 'rename-custom-type-column') return null

  return (
    <>
      <Flash {...testIdProps('column-settings-banner')} variant="warning" aria-live="polite" className={styles.Flash}>
        <div className={styles.Box}>
          <div>
            <Octicon icon={AlertIcon} className={styles.Octicon} />
          </div>
          <div className={styles.Box_1}>
            <Heading as="h3" className={styles.Heading}>
              {ColumnBannerResources.IssueTypeRename.copy1}
            </Heading>
            {ColumnBannerResources.IssueTypeRename.copy2(column.name)}&nbsp;
            <Link target="_blank" rel="noopener noreferrer" href={ColumnBannerResources.IssueTypeRename.learnMoreLink}>
              {ColumnBannerResources.IssueTypeRename.learnMoreText}
            </Link>
          </div>
          <div className={styles.Box_2}>
            <Button ref={buttonRef} onClick={() => setIsRenameDialogOpen(true)}>
              {ColumnBannerResources.IssueTypeRename.actionPrimary}
            </Button>
          </div>
        </div>
      </Flash>
      {isRenameDialogOpen && (
        <MemexIssueTypeRenameDialog
          column={column}
          onCancel={() => {
            setIsRenameDialogOpen(false)
            setTimeout(() => buttonRef.current?.focus(), 100)
          }}
          onConfirm={() => {
            setIsRenameDialogOpen(false)
          }}
        />
      )}
    </>
  )
}
