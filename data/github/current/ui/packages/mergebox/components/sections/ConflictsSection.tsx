import {useAnalytics} from '@github-ui/use-analytics'
import useSafeState from '@github-ui/use-safe-state'
import {CheckIcon, FileIcon, StopIcon} from '@primer/octicons-react'
import {ActionList, Button, CircleOcticon, Flash, Link, LinkButton, Spinner, Tooltip} from '@primer/react'
import styles from './ConflictsSection.module.css'
import {Octicon} from '@primer/react/deprecated'
import {useQueryClient} from '@github-ui/react-query'
import {useId, useState} from 'react'

import {CenteredLoadingSpinner} from './common/CenteredLoadingSpinner'
import {ButtonWithDropdown} from './common/ButtonWithDropdown'
import {AlertIcon} from './common/AlertIcon'
import {HEADER_ICON_SIZE} from '../../constants'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import type {AdvisoryWorkspace, MergeStateStatus, ViewerUpdateMethods} from '../../types'
import {useUpdatePullRequestBranchMutation} from '../../hooks/mutations/use-update-pull-request-branch-mutation'

import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import type {ConflictMergeConditionPayload} from '../../page-data/payloads/merge-box'

function UpdateBranchOption({
  description,
  onSelect,
  selected,
  text,
  inactiveText,
}: {
  description?: string
  onSelect: () => void
  selected: boolean
  text: string
  inactiveText?: string
}) {
  return (
    <ActionList.Item selected={selected} onSelect={onSelect} inactiveText={inactiveText}>
      {text}
      <ActionList.Description variant="block">{description}</ActionList.Description>
    </ActionList.Item>
  )
}

/**
 *
 * Renders the "Resolve conflicts" link button and handles the inactive state if the viewer cannot resolve conflicts in the web.
 */
function ResolveConflictsButton({
  conflictsWebEditorPath,
  conflictsState,
  webEditorConflictResolution,
}: {
  conflictsWebEditorPath: string
  conflictsState: string
  webEditorConflictResolution: ConflictMergeConditionPayload['webEditorConflictResolution']
}) {
  if (conflictsState !== 'HAS_CONFLICTS') return null
  if (!webEditorConflictResolution) return null

  if (!webEditorConflictResolution.viewerCanResolve) {
    return (
      <Tooltip direction="nw" text={webEditorConflictResolution.viewerCannotResolve?.message || ''}>
        <Button inactive>Resolve conflicts</Button>
      </Tooltip>
    )
  }
  return <LinkButton href={conflictsWebEditorPath}>Resolve conflicts</LinkButton>
}

/**
 *
 * Renders the appropriate subtitle for the conflict resolution based on the reason the viewer cannot resolve the conflicts.
 */
function ConflictResolutionSubtitle({
  conflictsWebEditorPath,
  webEditorConflictResolution,
}: {
  conflictsWebEditorPath: string
  webEditorConflictResolution: ConflictMergeConditionPayload['webEditorConflictResolution']
}) {
  const reason = webEditorConflictResolution?.viewerCannotResolve?.reason

  switch (reason) {
    case 'INSUFFICIENT_ACCESS':
      return null
    case 'TOO_COMPLEX':
    case 'HEAD_BRANCH_PROTECTED':
    case 'ADMIN_DISABLED':
      return <span>Use the command line to resolve conflicts before continuing.</span>
    default:
      return (
        <span>
          Use the{' '}
          <Link inline href={conflictsWebEditorPath}>
            web editor
          </Link>{' '}
          or the command line to resolve conflicts before continuing.
        </span>
      )
  }
}

function AdvisoryWorkspaceSubtitle({
  advisoryWorkspacePath,
  advisoryWorkspaceId,
}: {
  advisoryWorkspacePath: string | null | undefined
  advisoryWorkspaceId: string | null | undefined
}) {
  return (
    <span>
      Merging must be performed from the{' '}
      <Link inline href={advisoryWorkspacePath || ''}>
        {advisoryWorkspaceId}
      </Link>{' '}
      advisory.
    </span>
  )
}

type SubtitleArgs = {
  baseRefName: string
  viewerLogin: string
  conflictsWebEditorPath: string
  conflictsCondition: ConflictMergeConditionPayload | undefined
  advisoryWorkspaceId: string | null | undefined
  advisoryWorkspacePath: string | null | undefined
}
export type ConflictsSectionStatuses =
  | 'NO_CONFLICTS'
  | 'PENDING'
  | 'OUT_OF_DATE'
  | 'HAS_CONFLICTS'
  | 'HAS_REBASE_CONFLICTS'
  | 'HAS_ADVISORY_WORKSPACE'
/**
 * The different states the conflicts section can be in, with their presentational values.
 */
const CONFLICT_SECTION_STATUSES: Record<
  ConflictsSectionStatuses,
  {
    heading: string
    subtitle: (args: SubtitleArgs) => JSX.Element | string
    icon: JSX.Element
  }
> = {
  NO_CONFLICTS: {
    heading: 'No conflicts with base branch',
    subtitle: () => 'Merging can be performed automatically.',
    icon: (
      <CircleOcticon
        icon={() => <CheckIcon size={16} />}
        className="bgColor-success-emphasis fgColor-onEmphasis"
        size={HEADER_ICON_SIZE}
      />
    ),
  },
  PENDING: {
    heading: 'Checking for the ability to merge automatically...',
    subtitle: () => "Hang in there while we check the branch's status.",
    icon: <CenteredLoadingSpinner sx={{mt: 0, width: 'auto'}} />,
  },
  OUT_OF_DATE: {
    heading: 'This branch is out-of-date with the base branch',
    subtitle: ({baseRefName, viewerLogin}) =>
      `Merge the latest changes from ${baseRefName} into this branch. This merge commit will be associated with ${viewerLogin}.`,
    icon: <AlertIcon />,
  },
  HAS_CONFLICTS: {
    heading: 'This branch has conflicts that must be resolved',
    subtitle: ({conflictsWebEditorPath, conflictsCondition}) => (
      <ConflictResolutionSubtitle
        conflictsWebEditorPath={conflictsWebEditorPath}
        webEditorConflictResolution={conflictsCondition?.webEditorConflictResolution}
      />
    ),
    icon: <AlertIcon />,
  },
  HAS_REBASE_CONFLICTS: {
    heading: 'This branch cannot be rebased due to conflicts',
    subtitle: () => '',
    icon: <AlertIcon />,
  },
  HAS_ADVISORY_WORKSPACE: {
    heading: 'No conflicts with base branch',
    subtitle: ({advisoryWorkspaceId, advisoryWorkspacePath}) => (
      <AdvisoryWorkspaceSubtitle
        advisoryWorkspaceId={advisoryWorkspaceId}
        advisoryWorkspacePath={advisoryWorkspacePath}
      />
    ),
    icon: (
      <CircleOcticon
        icon={() => <CheckIcon size={16} />}
        className="bgColor-success-emphasis fgColor-onEmphasis"
        size={HEADER_ICON_SIZE}
      />
    ),
  },
}

export type ConflictsSectionProps = {
  conflictsState: ConflictsSectionStatuses
  baseRefName: string
  headRefOid: string
  mergeStateStatus: MergeStateStatus
  resourcePath: string
  viewerCanUpdateBranch: boolean
  viewerLogin: string
  conflictsCondition: ConflictMergeConditionPayload
  canUserPushToBase: boolean
  advisoryWorkspace: AdvisoryWorkspace
  viewerUpdateMethods: ViewerUpdateMethods | null
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
  resourcePath,
  viewerCanUpdateBranch,
  viewerUpdateMethods,
  viewerLogin,
  conflictsCondition,
  conflictsState,
  canUserPushToBase,
  advisoryWorkspace,
}: ConflictsSectionProps) {
  const defaultUpdateBranchMethod =
    viewerUpdateMethods?.find(updateMethod => updateMethod.isDefault === true)?.name || 'MERGE'

  const [selectedUpdateMethod, setSelectedUpdateMethod] = useState<'MERGE' | 'REBASE'>(defaultUpdateBranchMethod)
  const [isUpdating, setIsUpdating] = useSafeState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)
  const {sendAnalyticsEvent} = useAnalytics()
  const conflictsSectionAriaId = useId()
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()

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

  const conflictsWebEditorPath = `${resourcePath}/conflicts`

  const conflicts = conflictsCondition.conflicts ?? []

  function updateBranchButtonText() {
    return selectedUpdateMethod === 'MERGE' ? 'Update branch' : 'Rebase branch'
  }

  function updateBranchButtonLoadingAnnouncement() {
    return selectedUpdateMethod === 'MERGE' ? 'Updating branch' : 'Rebasing branch'
  }

  const showUpdateBranchButton =
    (conflictsState === 'OUT_OF_DATE' || conflictsState === 'NO_CONFLICTS' || conflictsState === 'PENDING') &&
    viewerCanUpdateBranch

  // only list files if user can resolve conflict or user can push to head (aka has sufficient access)
  const shouldListConflictingFiles =
    conflictsState === 'HAS_CONFLICTS' &&
    (conflictsCondition.webEditorConflictResolution?.viewerCanResolve ||
      conflictsCondition.webEditorConflictResolution?.viewerCannotResolve?.reason !== 'INSUFFICIENT_ACCESS')

  const advisoryWorkspaceId = advisoryWorkspace?.advisoryWorkspaceId
  const advisoryWorkspacePath = advisoryWorkspace?.advisoryWorkspacePath

  const unBlockedUpdateBranchMethods = viewerUpdateMethods?.filter(
    updateMethod => updateMethod.allowableStatus === 'ALLOWED' || updateMethod.allowableStatus === 'UNAVAILABLE',
  )

  const viewerCanUseMergeToUpdate = viewerUpdateMethods?.find(
    updateMethod => updateMethod.name === 'MERGE' && updateMethod.allowableStatus === 'ALLOWED',
  )
  const viewerCanUseRebaseToUpdate = viewerUpdateMethods?.find(
    updateMethod => updateMethod.name === 'REBASE' && updateMethod.allowableStatus === 'ALLOWED',
  )
  const rebaseUpdateMethodUnavailable = viewerUpdateMethods?.find(
    updateMethod => updateMethod.name === 'REBASE' && updateMethod.allowableStatus === 'UNAVAILABLE',
  )
  const rebaseUnavailableReason = viewerUpdateMethods?.find(updateMethod => updateMethod.name === 'REBASE')
    ?.failureReason

  // Conditionally adds options to the Update branch dropdown depending on whether they're allowed
  // or temporarily unavailable.
  function updateBranchList() {
    if (viewerUpdateMethods) {
      return (
        <ActionList selectionVariant="single" showDividers>
          {viewerCanUseMergeToUpdate && (
            <UpdateBranchOption
              description="The merge commit will be associated with your account."
              selected={defaultUpdateBranchMethod === 'MERGE'}
              text="Update with merge commit"
              onSelect={() => {
                sendAnalyticsEvent(
                  'conflicts_section.select_merge_commit_method',
                  'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
                )
                setSelectedUpdateMethod('MERGE')
              }}
            />
          )}
          {viewerCanUseRebaseToUpdate && (
            <UpdateBranchOption
              description="This pull request will be rebased on top of the latest changes and then force pushed."
              selected={defaultUpdateBranchMethod === 'REBASE'}
              text="Update with rebase"
              onSelect={() => {
                sendAnalyticsEvent(
                  'conflicts_section.select_rebase_method',
                  'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
                )
                setSelectedUpdateMethod('REBASE')
              }}
            />
          )}
          {rebaseUpdateMethodUnavailable && (
            <UpdateBranchOption
              inactiveText={rebaseUnavailableReason || 'This branch cannot be rebased at this time.'}
              selected={defaultUpdateBranchMethod === 'REBASE'}
              text="Update with rebase"
              onSelect={() => {
                sendAnalyticsEvent(
                  'conflicts_section.select_rebase_method',
                  'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
                )
                setSelectedUpdateMethod('REBASE')
              }}
            />
          )}
        </ActionList>
      )
    } else {
      // Delete this once ff :mergebox_update_branch_methods is removed
      return (
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
      )
    }
  }

  return (
    <section
      aria-label="Conflicts"
      className="border-bottom borderColor-muted"
      aria-describedby={conflictsSectionAriaId}
    >
      <div className="d-flex flex-column width-full overflow-hidden">
        <MergeBoxSectionHeader
          headerId={conflictsSectionAriaId}
          icon={CONFLICT_SECTION_STATUSES[conflictsState].icon}
          title={
            <>
              {CONFLICT_SECTION_STATUSES[conflictsState].heading}
              {isUpdating && <Spinner size="small" sx={{ml: 2}} />}
            </>
          }
          subtitle={
            canUserPushToBase
              ? CONFLICT_SECTION_STATUSES[conflictsState].subtitle({
                  baseRefName,
                  viewerLogin,
                  conflictsWebEditorPath,
                  conflictsCondition,
                  advisoryWorkspaceId,
                  advisoryWorkspacePath,
                })
              : 'Changes can be cleanly merged.'
          }
          rightSideContent={
            <>
              {showUpdateBranchButton && (
                <ButtonWithDropdown
                  hideSecondaryButton={unBlockedUpdateBranchMethods?.length === 1}
                  loading={isUpdating}
                  loadingAnnouncement={updateBranchButtonLoadingAnnouncement()}
                  secondaryButtonAriaLabel="Update branch options"
                  actionList={updateBranchList()}
                  onPrimaryButtonClick={handleUpdateBranch}
                >
                  {updateBranchButtonText()}
                </ButtonWithDropdown>
              )}
              <ResolveConflictsButton
                conflictsWebEditorPath={conflictsWebEditorPath}
                conflictsState={conflictsState}
                webEditorConflictResolution={conflictsCondition.webEditorConflictResolution}
              />
            </>
          }
        >
          {shouldListConflictingFiles && (
            <div className="ml-n3">
              <ActionList className="py-0 overflow-hidden">
                {conflicts.map(conflictPath => {
                  return (
                    <ActionList.Item key={conflictPath}>
                      <ActionList.LeadingVisual className="fgColor-muted">
                        <FileIcon />
                      </ActionList.LeadingVisual>
                      <span className={`input-monospace f6 ${styles.selectable}`}>{conflictPath}</span>
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
