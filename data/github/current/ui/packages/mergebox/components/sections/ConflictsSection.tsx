import {useAnalytics} from '@github-ui/use-analytics'
import useSafeState from '@github-ui/use-safe-state'
import {CheckIcon, FileIcon, StopIcon} from '@primer/octicons-react'
import {ActionList, CircleOcticon, Flash, Link, LinkButton, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useId, useState} from 'react'

import {CenteredLoadingSpinner} from './common/CenteredLoadingSpinner'
import {ButtonWithDropdown} from './common/ButtonWithDropdown'
import {AlertIcon} from './common/AlertIcon'
import {HEADER_ICON_SIZE} from '../../constants'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import type {MergeStateStatus, PullRequestMergeConditionResult} from '../../types'
import {useUpdatePullRequestBranchMutation} from '../../hooks/mutations/use-update-pull-request-branch-mutation'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'

function UpdateBranchOption({
  description,
  onSelect,
  selected,
  text,
}: {
  description: string
  onSelect: () => void
  selected: boolean
  text: string
}) {
  return (
    <ActionList.Item selected={selected} onSelect={onSelect}>
      {text}
      <ActionList.Description variant="block">{description}</ActionList.Description>
    </ActionList.Item>
  )
}

const heading: {[key: string]: string} = {
  NO_CONFLICTS: 'No conflicts with base branch',
  PENDING: 'Checking for the ability to merge automatically...',
  OUT_OF_DATE: 'This branch is out-of-date with the base branch',
  HAS_CONFLICTS: 'This branch has conflicts that must be resolved',
  COMPLEX_CONFLICTS: 'This branch has conflicts that must be resolved',
}

const icons: {[key: string]: JSX.Element} = {
  NO_CONFLICTS: (
    <CircleOcticon
      icon={() => <CheckIcon size={16} />}
      className="bgColor-success-emphasis fgColor-onEmphasis"
      size={HEADER_ICON_SIZE}
    />
  ),
  PENDING: <CenteredLoadingSpinner sx={{mt: 0, width: 'auto'}} />,
  OUT_OF_DATE: <AlertIcon />,
  HAS_CONFLICTS: <AlertIcon />,
  COMPLEX_CONFLICTS: <AlertIcon />,
}

type ConflictMergeCondition = {
  conflicts?: string[] | null | undefined
  isConflictResolvableInWeb?: boolean | null | undefined
  message: string | null | undefined
  result: PullRequestMergeConditionResult
}

export type ConflictsSectionProps = {
  baseRefName: string
  headRefOid: string
  mergeStateStatus: MergeStateStatus
  resourcePath: string
  viewerCanUpdateBranch: boolean
  viewerLogin: string
  conflictsCondition: ConflictMergeCondition | undefined
  canUserPushToBase: boolean
}

/**
 *
 * Renders the pull request "git" merge status
 * If there are merge conflicts, describes them.
 * Allows the user to update a branch if it's out of date.
 * Also: It returns null if the merge state status is BLOCKED because this component doesn't care about BLOCKED.
 */
export function ConflictsSection({
  baseRefName,
  headRefOid,
  mergeStateStatus,
  resourcePath,
  viewerCanUpdateBranch,
  viewerLogin,
  conflictsCondition,
  canUserPushToBase,
}: ConflictsSectionProps) {
  const [selectedUpdateMethod, setSelectedUpdateMethod] = useState<'MERGE' | 'REBASE'>('MERGE')
  const [isUpdating, setIsUpdating] = useSafeState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)
  const {sendAnalyticsEvent} = useAnalytics()
  const conflictsSectionAriaId = useId()
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()

  const onSuccessfulUpdate = async () => {
    await queryClient.refetchQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})

    setIsUpdating(false)
  }

  const handleError = (e: Error) => {
    setIsUpdating(false)
    setErrorMessage(e.message)
  }

  const {mutate: updatePullRequestBranch} = useUpdatePullRequestBranchMutation({
    onSuccess: onSuccessfulUpdate,
    onError: handleError,
  })

  const handleUpdateBranch = () => {
    if (isUpdating) return

    setIsUpdating(true)
    setErrorMessage(null)
    updatePullRequestBranch({
      updateMethod: selectedUpdateMethod,
      expectedHeadOid: headRefOid,
    })
    sendAnalyticsEvent('conflicts_section.update_branch', 'MERGEBOX_CONFLICTS_SECTION_UPDATE_BRANCH_BUTTON')
  }

  let conflictsState = 'PENDING'
  const conflictsWebEditorPath = `${resourcePath}/conflicts`

  if (!conflictsCondition) return null
  if (!('conflicts' in conflictsCondition) || !('result' in conflictsCondition)) return null
  const conflicts = conflictsCondition.conflicts ?? []

  if (mergeStateStatus === 'BEHIND') {
    conflictsState = 'OUT_OF_DATE'
  } else if (mergeStateStatus === 'UNKNOWN') {
    conflictsState = 'PENDING'
  } else if (mergeStateStatus === 'CLEAN' || mergeStateStatus === 'UNSTABLE' || mergeStateStatus === 'HAS_HOOKS') {
    conflictsState = 'NO_CONFLICTS'
  } else if (mergeStateStatus === 'DIRTY' && conflictsCondition.result === 'FAILED' && conflicts.length > 0) {
    if ('isConflictResolvableInWeb' in conflictsCondition && conflictsCondition.isConflictResolvableInWeb) {
      conflictsState = 'HAS_CONFLICTS'
    } else {
      conflictsState = 'COMPLEX_CONFLICTS'
    }
  } else if (mergeStateStatus === 'BLOCKED') {
    conflictsState = 'OUT_OF_DATE'
  }

  function updateBranchButtonText() {
    if (selectedUpdateMethod === 'MERGE' && isUpdating) {
      return (
        <div className="d-flex flex-row flex-items-center">
          <Spinner size="small" sx={{mr: 1}} />
          <span> Updating branch... </span>
        </div>
      )
    }
    if (selectedUpdateMethod === 'MERGE' && !isUpdating) {
      return <span> Update branch </span>
    }
    if (isUpdating) {
      return (
        <div className="d-flex flex-row flex-items-center">
          <Spinner size="small" sx={{mr: 1}} />
          <span> Rebasing branch... </span>
        </div>
      )
    }

    return <span> Rebase branch </span>
  }

  const showUpdateBranchButton =
    (conflictsState === 'OUT_OF_DATE' || conflictsState === 'NO_CONFLICTS' || conflictsState === 'PENDING') &&
    viewerCanUpdateBranch

  const subtitle: {[key: string]: string | JSX.Element} = {
    NO_CONFLICTS: 'Merging can be performed automatically.',
    PENDING: "Hang in there while we check the branch's status.",
    OUT_OF_DATE: `Merge the latest changes from ${baseRefName} into this branch. This merge commit will be associated with ${viewerLogin}.`,
    HAS_CONFLICTS: (
      <span>
        Use the{' '}
        <Link inline href={conflictsWebEditorPath} underline>
          web editor
        </Link>{' '}
        or the command line to resolve conflicts before continuing. Actions workflows will not trigger on activity from
        this pull request while it has merge conflicts.
      </span>
    ),
    COMPLEX_CONFLICTS:
      'Resolve conflicts then push again. These conflicts are too complex to resolve in the web editor. Actions workflows will not trigger on activity from this pull request while it has merge conflicts.',
  }

  if (mergeStateStatus === 'BLOCKED' && !viewerCanUpdateBranch) return null

  return (
    <section
      aria-label="Conflicts"
      className="border-bottom borderColor-muted"
      aria-describedby={conflictsSectionAriaId}
    >
      <div className="d-flex flex-column width-full overflow-hidden">
        <MergeBoxSectionHeader
          headerId={conflictsSectionAriaId}
          icon={icons[conflictsState]}
          title={
            <>
              {heading[conflictsState]}
              {isUpdating && <Spinner size="small" sx={{ml: 2}} />}
            </>
          }
          subtitle={canUserPushToBase ? subtitle[conflictsState] : 'Changes can be cleanly merged.'}
          rightSideContent={
            <>
              {showUpdateBranchButton && (
                <ButtonWithDropdown
                  inactive={isUpdating}
                  inactiveTooltipText="Updating a branch is not available at this time."
                  secondaryButtonAriaLabel="Update branch options"
                  actionList={
                    <ActionList selectionVariant="single" showDividers>
                      <UpdateBranchOption
                        description="The merge commit will be associated with your account."
                        selected={selectedUpdateMethod === 'MERGE'}
                        text="Update with merge commit"
                        onSelect={() => {
                          sendAnalyticsEvent(
                            'conflicts_section.select_merge_commit_method',
                            'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
                          )
                          setSelectedUpdateMethod('MERGE')
                        }}
                      />
                      <UpdateBranchOption
                        description="This pull request will be rebased on top of the latest changes and then force pushed."
                        selected={selectedUpdateMethod === 'REBASE'}
                        text="Update with rebase"
                        onSelect={() => {
                          sendAnalyticsEvent(
                            'conflicts_section.select_rebase_method',
                            'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
                          )
                          setSelectedUpdateMethod('REBASE')
                        }}
                      />
                    </ActionList>
                  }
                  onPrimaryButtonClick={handleUpdateBranch}
                >
                  {updateBranchButtonText()}
                </ButtonWithDropdown>
              )}
              {conflictsState === 'HAS_CONFLICTS' && (
                <LinkButton href={conflictsWebEditorPath} underline>
                  Resolve conflicts
                </LinkButton>
              )}
            </>
          }
        >
          {(conflictsState === 'HAS_CONFLICTS' || conflictsState === 'COMPLEX_CONFLICTS') && (
            <div className="ml-n3">
              <ActionList className="py-0 overflow-hidden">
                {conflicts.map(conflictPath => {
                  return (
                    <ActionList.Item key={conflictPath}>
                      <ActionList.LeadingVisual className="fgColor-muted">
                        <FileIcon />
                      </ActionList.LeadingVisual>
                      <span className="input-monospace f6">{conflictPath}</span>
                    </ActionList.Item>
                  )
                })}
              </ActionList>
            </div>
          )}
        </MergeBoxSectionHeader>
        {errorMessage && (
          <Flash className="m-3" variant="danger">
            <Octicon className="mr-2" icon={StopIcon} />
            {errorMessage}
          </Flash>
        )}
      </div>
    </section>
  )
}
