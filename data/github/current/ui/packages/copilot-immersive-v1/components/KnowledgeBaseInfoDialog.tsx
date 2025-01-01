import type {Docset} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {encodePart} from '@github-ui/paths'
import {BookIcon, RepoIcon} from '@primer/octicons-react'
import {ActionList, Dialog, Heading} from '@primer/react'
import {type RefObject, useId} from 'react'

import styles from './KnowledgeBaseInfoDialog.module.css'

interface KnowledgeBaseInfoDialogProps {
  docset: Docset
  onClose: () => void
  returnFocusRef: RefObject<HTMLElement>
}

export function KnowledgeBaseInfoDialog({docset, onClose, returnFocusRef}: KnowledgeBaseInfoDialogProps) {
  const reposLabelId = useId()

  return (
    <Dialog
      title={
        <>
          <BookIcon className={styles.icon} /> {docset.name}
        </>
      }
      onClose={onClose}
      returnFocusRef={returnFocusRef}
    >
      {docset.description && <p>{docset.description}</p>}
      <Heading as="h2" variant="small" id={reposLabelId} className={styles.heading}>
        Included repositories
      </Heading>
      <ActionList variant="full" aria-labelledby={reposLabelId}>
        {docset.repos?.map(repo => (
          <ActionList.LinkItem href={`/${encodePart(repo)}`} key={repo}>
            <ActionList.LeadingVisual>
              <RepoIcon />
            </ActionList.LeadingVisual>
            {repo}
          </ActionList.LinkItem>
        ))}
      </ActionList>
    </Dialog>
  )
}
