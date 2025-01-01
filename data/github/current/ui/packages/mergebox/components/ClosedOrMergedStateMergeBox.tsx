import {branchPath} from '@github-ui/paths'
import useSafeState from '@github-ui/use-safe-state'
import {SyncIcon} from '@primer/octicons-react'
import {BranchName, Button, Link} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'

import {MergeBoxSectionHeader} from './sections/common/MergeBoxSectionHeader'
import type {DeprovisionableCodespaces, PullRequestState} from '../types'
import {useDeleteHeadRefMutation} from '../hooks/mutations/use-delete-head-ref-mutation'
import {clsx} from 'clsx'
import styles from './ClosedOrMergedStateMergeBox.module.css'
import {useCleanupCodespacesMutation} from '../hooks/mutations/use-cleanup-codespaces-mutation'
import {announce} from '@github-ui/aria-live'
import {useRef} from 'react'
import type {Repository} from '../page-data/payloads/merge-box'

export interface Props {
  // We only care about the closed and merged state
  state: PullRequestState

  // All of this needed only to create the branch path.
  headRefName: string
  headRepository: Repository
  baseRepository: Repository
  isCrossRepo: boolean
  viewerCanDeleteHeadRef: boolean
  deprovisionableCodespaces: DeprovisionableCodespaces
  viewerCanRestoreHeadRef: boolean
}

/*
 * Displays closed and merged states for the merge box
 * For closed, only displays if the viewer can delete the head ref
 * For merged, only displays if the viewer can either delete the head ref or restore it
 */
export function ClosedOrMergedStateMergeBox({
  state,
  isCrossRepo,
  headRefName,
  headRepository,
  baseRepository,
  viewerCanDeleteHeadRef,
  viewerCanRestoreHeadRef,
  deprovisionableCodespaces,
}: Props) {
  const [error, setError] = useSafeState<Error | undefined>()
  const confirmationButtonRef = useRef<HTMLButtonElement>(null)
  const [isConfirmationDialogOpen, setIsConfirmationDialogOpen] = useSafeState(false)

  const codespaceCount = deprovisionableCodespaces ? deprovisionableCodespaces.count : 0
  const showCodespaceDelete = viewerCanRestoreHeadRef && deprovisionableCodespaces && codespaceCount > 0
  const codespaceText = codespaceCount > 1 ? 'codespaces' : 'codespace'

  const {mutate: deleteHeadRef, isPending: deleteHeadRefIsPending} = useDeleteHeadRefMutation({
    onError: (e: Error) => {
      setError(e)
    },
  })

  const handleDeleteRef = () => {
    setError(undefined)
    deleteHeadRef(undefined)
  }

  const {mutate: deleteCodespace, isPending: deleteCodespaceIsPending} = useCleanupCodespacesMutation({
    onError: (e: Error) => {
      setIsConfirmationDialogOpen(false)
      setError(e)
      confirmationButtonRef.current?.focus()
    },
  })

  const handleDeleteCodespaces = () => {
    setError(undefined)

    deleteCodespace(undefined, {
      onSuccess: () => {
        setIsConfirmationDialogOpen(false)
        setTimeout(() => announce(`Deleting ${codespaceText}.`), 1000)
      },
    })
  }

  const handleOpenConfirmation = () => {
    setError(undefined)
    setIsConfirmationDialogOpen(true)
  }

  const generateRepositoryURL = (): string => {
    if (!headRepository || !headRepository.name) {
      return ''
    }
    return branchPath({
      owner: headRepository.ownerLogin,
      repo: headRepository.name,
      branch: headRefName,
    })
  }

  const headingText = () => {
    if (showCodespaceDelete) {
      return 'Branch successfully deleted'
    } else if (state === 'MERGED') {
      return 'Pull request successfully merged and closed'
    } else {
      return 'Closed with unmerged commits'
    }
  }

  const actionButton = (
    <Button loading={deleteHeadRefIsPending} loadingAnnouncement="Deleting branch" onClick={handleDeleteRef}>
      Delete branch
    </Button>
  )

  const codespaceButton = (
    <Button ref={confirmationButtonRef} onClick={handleOpenConfirmation}>
      Delete {codespaceText}
    </Button>
  )

  const spanWithToggleClass = <span id="js-pull-restorable" className="d-none" />

  const repoSettingsPath = `${headRepository?.url}/settings`

  // If the branch can be deleted, show the 'Delete branch' button.
  // If the branch cannot be deleted and a codespace exists, show the 'Delete codespace' button.
  // Otherwise, append the class responsible for toggling the restore branch button on the Timeline.
  const getRightSideContent = () => {
    if (viewerCanDeleteHeadRef) {
      return actionButton
    } else if (showCodespaceDelete) {
      return codespaceButton
    }
    return spanWithToggleClass
  }

  const subtitle = () => {
    if (state === 'MERGED') {
      if (viewerCanDeleteHeadRef) {
        return (
          <>
            You&#39;re all set &#8212; the{' '}
            <BranchName className={clsx(styles.branchName, 'd-inline wb-break-all')} href={generateRepositoryURL()}>
              {headRefName}
            </BranchName>{' '}
            branch can be safely deleted.
            {isCrossRepo && (
              <>
                {' '}
                If you wish, you can also delete this fork of{' '}
                <strong>{`${baseRepository?.ownerLogin}/${baseRepository?.name}`}</strong> in the{' '}
                <Link href={repoSettingsPath} inline>
                  settings
                </Link>
                .
              </>
            )}
          </>
        )
      } else if (showCodespaceDelete) {
        return (
          <>
            You&#39;re all set &#8212; the {codespaceCount} {codespaceText} for head branch can be safely deleted. You
            can also manage your codespaces in{' '}
            <Link inline href={deprovisionableCodespaces.repositoryCodespacePath || ''}>
              settings.
            </Link>{' '}
          </>
        )
      } else {
        return <>You&#39;re all set &#8212; the branch has been merged.</>
      }
    } else {
      if (viewerCanDeleteHeadRef) {
        return (
          <>
            This pull request is closed, but the <BranchName href={generateRepositoryURL()}>{headRefName}</BranchName>{' '}
            branch has unmerged commits.
          </>
        )
      } else {
        return <>This pull request is closed.</>
      }
    }
  }

  const mainContent = () => {
    if (error) {
      const errorIsTransient = error.cause !== 404
      return (
        <MergeBoxSectionHeader
          title={
            error.message === 'Some codespaces could not be deleted.'
              ? `Couldn't delete ${codespaceText} `
              : "Couldn't update branch"
          }
          subtitle={error.message}
          rightSideContent={
            errorIsTransient ? (
              <Button disabled={deleteHeadRefIsPending} leadingVisual={SyncIcon} onClick={() => setError(undefined)}>
                Try again
              </Button>
            ) : undefined
          }
        />
      )
    } else {
      return (
        <>
          <Dialog
            aria-labelledby="delete-codespaces-dialog-title"
            isOpen={isConfirmationDialogOpen}
            returnFocusRef={confirmationButtonRef}
            onDismiss={() => setIsConfirmationDialogOpen(false)}
          >
            <Dialog.Header id="delete-codespaces-dialog-title">Delete Codespace?</Dialog.Header>
            <div className="p-3">
              <span>
                Are you sure you want to delete {codespaceCount} {codespaceText} for the head branch?
              </span>
              <div className="d-flex flex-justify-end mt-3">
                <Button
                  className="mr-1"
                  inactive={deleteCodespaceIsPending}
                  onClick={() => {
                    if (!deleteCodespaceIsPending) {
                      setIsConfirmationDialogOpen(false)
                      confirmationButtonRef.current?.focus()
                    }
                  }}
                >
                  Cancel
                </Button>
                <Button
                  className="mr-1"
                  variant="danger"
                  loading={deleteCodespaceIsPending}
                  loadingAnnouncement={`Deleting ${codespaceText}.`}
                  onClick={handleDeleteCodespaces}
                >
                  {`Delete ${codespaceText}`}
                </Button>
              </div>
            </div>
          </Dialog>
          <MergeBoxSectionHeader title={headingText()} subtitle={subtitle()} rightSideContent={getRightSideContent()} />
        </>
      )
    }
  }

  return mainContent()
}
