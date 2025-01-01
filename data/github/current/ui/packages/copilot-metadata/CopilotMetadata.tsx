import {issuePath} from '@github-ui/paths'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {ArrowLeftIcon} from '@primer/octicons-react'
import {Button, Spinner, UnderlineNav} from '@primer/react'

import {ContactList} from './Contact'
import styles from './CopilotMetadata.module.css'
import {useCopilotMetadata} from './hooks/use-get-copilot-metadata'
import type {MakeCAPIRequestType, FileReference} from './types'

export const CopilotMetadata = ({
  currentTab,
  setCurrentTab,
  loading = true,
  setLoading,
  makeCAPIRequest,
  fileContext,
}: {
  currentTab: string
  setCurrentTab: (tab: string) => void
  loading: boolean
  setLoading: (loadingState: boolean) => void
  makeCAPIRequest: MakeCAPIRequestType
  fileContext?: FileReference
}) => {
  const owner = fileContext?.repoOwner
  const repo = fileContext?.repoName
  const queryParams = new URLSearchParams(ssrSafeWindow?.location.search)
  const issueNumber = queryParams.get('issue') || ''

  const linkedIssuePath =
    owner && repo && issueNumber ? issuePath({owner, repo, issueNumber: Number(issueNumber)}) : undefined

  const {collaborators} = useCopilotMetadata({fileContext, setLoading, issueNumber, makeCAPIRequest})

  const redirectToReferrer = () => {
    if (linkedIssuePath) {
      window.location.href = linkedIssuePath
    }
  }

  return (
    <div>
      <UnderlineNav aria-label="Repository">
        <UnderlineNav.Item
          aria-current={currentTab === 'chat' ? 'page' : undefined}
          onSelect={() => setCurrentTab('chat')}
        >
          Chat
        </UnderlineNav.Item>
        <UnderlineNav.Item
          aria-current={currentTab === 'directory' ? 'page' : undefined}
          onSelect={() => {
            if (!loading && collaborators?.length) setCurrentTab('directory')
          }}
        >
          <div className={styles['tab-container']}>
            <span {...(!collaborators?.length ? {className: styles['muted']} : {})}>
              {collaborators?.length || loading ? 'Directory' : 'Directory unavailable'}
            </span>
            {loading && (
              <div className={styles['spinner-container']}>
                <Spinner size="small" />
              </div>
            )}
          </div>
        </UnderlineNav.Item>
      </UnderlineNav>

      {currentTab === 'directory' && (
        <div className={styles['metadata-container']}>
          <div>
            <ContactList contacts={collaborators} />
          </div>
          {linkedIssuePath && (
            <div className={styles['referrer-button']}>
              <Button variant="link" leadingVisual={ArrowLeftIcon} onClick={redirectToReferrer}>
                {`Return to Issue${issueNumber ? ` ${issueNumber}` : ''}`}
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
