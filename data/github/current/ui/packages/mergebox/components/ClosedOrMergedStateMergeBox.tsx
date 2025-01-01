import {branchPath} from '@github-ui/paths'
import useSafeState from '@github-ui/use-safe-state'
import {SyncIcon} from '@primer/octicons-react'
import {BranchName, Button, Spinner} from '@primer/react'

import {MergeBoxSectionHeader} from './sections/common/MergeBoxSectionHeader'
import {borderColorClassForStatus, Status} from '../helpers/mergeability-status'
import type {PullRequestState} from '../types'
import {useDeleteHeadRefMutation} from '../hooks/mutations/use-delete-head-ref-mutation'
import {useRestoreHeadRefMutation} from '../hooks/mutations/use-restore-head-ref-mutation'
import {clsx} from 'clsx'
import styles from './ClosedOrMergedStateMergeBox.module.css'

export interface Props {
  // We only care about the closed and merged state
  state: PullRequestState

  // All of this needed only to create the branch path.
  headRefName: string
  headRepository:
    | {
        ownerLogin: string
        name: string
      }
    | null
    | undefined

  // These states are mutually exclusive
  viewerCanDeleteHeadRef: boolean
  viewerCanRestoreHeadRef: boolean
}

/*
 * Displays closed and merged states for the merge box
 * For closed, only displays if the viewer can delete the head ref
 * For merged, only displays if the viewer can either delete the head ref or restore it
 */
export function ClosedOrMergedStateMergeBox({
  state,
  headRefName,
  headRepository,
  viewerCanDeleteHeadRef,
  viewerCanRestoreHeadRef,
}: Props) {
  const [error, setError] = useSafeState<Error | undefined>()

  const {mutate: deleteHeadRef, isPending: isDeletePending} = useDeleteHeadRefMutation({
    onError: (e: Error) => {
      setError(e)
    },
  })

  const {mutate: restoreHeadRef, isPending: isRestorePending} = useRestoreHeadRefMutation({
    onError: (e: Error) => {
      setError(e)
    },
  })

  const isPending = isDeletePending || isRestorePending

  const handleDeleteRef = () => {
    if (isPending) return

    setError(undefined)
    deleteHeadRef(undefined)
  }

  const handleRestoreRef = () => {
    if (isPending) return

    setError(undefined)
    restoreHeadRef(undefined)
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

  const headingText =
    state === 'MERGED' ? 'Pull request successfully merged and closed' : 'Closed with unmerged commits'
  const borderColor =
    state === 'MERGED' ? borderColorClassForStatus(Status.Merged) : borderColorClassForStatus(Status.Closed)

  const actionButton = () => {
    if (viewerCanDeleteHeadRef) {
      return (
        <Button aria-disabled={isPending} onClick={handleDeleteRef} inactive={isPending}>
          {isPending ? (
            <div className="d-flex flex-row flex-items-center">
              <Spinner size={'small'} sx={{mr: 1}} />
              <span>Deleting branch...</span>
            </div>
          ) : (
            <span>Delete branch</span>
          )}
        </Button>
      )
    } else if (viewerCanRestoreHeadRef) {
      return (
        <Button inactive={isPending} onClick={handleRestoreRef} aria-disabled={isPending}>
          {isPending ? (
            <div className="d-flex flex-row flex-items-center">
              <Spinner size={'small'} sx={{mr: 1}} />
              <span>Restoring branch...</span>
            </div>
          ) : (
            <span>Restore branch</span>
          )}
        </Button>
      )
    }
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
          </>
        )
      } else if (viewerCanRestoreHeadRef) {
        return (
          <>
            You&#39;re all set &#8212; the{' '}
            <BranchName className={clsx(styles.branchName, 'd-inline wb-break-all')} as="span">
              {headRefName}
            </BranchName>{' '}
            branch has been merged and deleted.
          </>
        )
      }
    } else {
      if (viewerCanDeleteHeadRef) {
        return (
          <>
            This pull request is closed, but the <BranchName href={generateRepositoryURL()}>{headRefName}</BranchName>{' '}
            branch has unmerged commits.
          </>
        )
      } else if (viewerCanRestoreHeadRef) {
        return (
          <>
            This pull request is closed and the <BranchName href={generateRepositoryURL()}> {headRefName} </BranchName>
            branch has been deleted.
          </>
        )
      }
    }
  }

  const mainContent = () => {
    if (error) {
      const errorIsTransient = error.cause !== 404
      return (
        <MergeBoxSectionHeader
          title="Couldn&#39;t update branch"
          subtitle={error.message ?? 'An error occurred while trying to update the branch'}
          rightSideContent={
            errorIsTransient ? (
              <Button disabled={isPending} leadingVisual={SyncIcon} onClick={() => setError(undefined)}>
                Try again
              </Button>
            ) : undefined
          }
        />
      )
    } else {
      return <MergeBoxSectionHeader title={headingText} subtitle={subtitle()} rightSideContent={actionButton()} />
    }
  }

  if (state === 'OPEN' || (!viewerCanDeleteHeadRef && !viewerCanRestoreHeadRef)) {
    return null
  }

  return (
    <div className="d-flex flex-row position-relative">
      <div className={`width-full border ${borderColor} rounded-2`}>{mainContent()}</div>
    </div>
  )
}
