import {useAnalytics} from '@github-ui/use-analytics'
import {ActionList, Button, Flash, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useEffect, useRef, useState} from 'react'
import {clsx} from 'clsx'

import {MergeAction, MergeQueueMethod} from '../../../types'
import {ButtonWithDropdown} from '../common/ButtonWithDropdown'
import {mergeQueueButtonText} from '../../../helpers/merge-button-text'
import {StopIcon} from '@primer/octicons-react'
import {
  type Props as DirectMergeActionsSectionProps,
  DirectMergeActionsSection,
  type MergeButtonFocusProps,
} from './DirectMergeActionsSection'
import {MergeDropdownOption} from './MergeDropdownOption'
import type {
  MergeStateStatus,
  ViewerMergeActions,
  MergeQueue,
  AutoMergeRequest,
  PullRequestMergeRequirementsState,
  AdvisoryWorkspace,
} from '../../../types'
import {useDisableAutoMergeMutation} from '../../../hooks/mutations/use-disable-auto-merge-mutation'
import {useEnableAutoMergeMutation} from '../../../hooks/mutations/use-enable-auto-merge-mutation'
import {BypassMergeRequirementsToggle} from './BypassMergeRequirementsToggle'
import type {
  PullRequestMergeRequirementsPayload,
  JSONAPIPullRequestPayload,
} from '../../../page-data/payloads/merge-box'
import type {Status} from '../../../helpers/mergeability-status'
import useSafeState from '@github-ui/use-safe-state'
import {MergeSectionActions} from './MergeSectionActions'
import {calculateMergeability} from '../../../helpers/mergeability-helpers'
import type {MergeBoxRollupStatus} from '../../../helpers/merge-box-status-calculator/types'

const AUTOMERGE_DOCS_LINK =
  'https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request'

export type AddToMergeQueueSectionProps = {
  autoMergeRequest: AutoMergeRequest
  baseRefName: string
  pullRequestId: string
  // TODO: remove "?" when :merge_box_hide_sections Feature Flag is removed
  handleConfirmingMergeInfo?: (isConfirming: boolean) => void
  isDraft: boolean
  isInMergeQueue: boolean
  mergeQueue: MergeQueue
  mergeRequirementsState: PullRequestMergeRequirementsState
  mergeStateStatus: MergeStateStatus
  mergeBoxRollupStatus: MergeBoxRollupStatus
  status: Status
  viewerCanAddAndRemoveFromMergeQueue: JSONAPIPullRequestPayload['viewerCanAddAndRemoveFromMergeQueue']
  viewerCanAddToMergeQueueSolo: JSONAPIPullRequestPayload['viewerCanAddToMergeQueueSolo']
}

/**
 * Renders the merge queue button and provides the ability to select from the merge queue methods
 */
function AddToMergeQueueSection({
  autoMergeRequest,
  baseRefName,
  handleConfirmingMergeInfo,
  isDraft,
  isInMergeQueue,
  mergeQueue,
  mergeRequirementsState,
  mergeStateStatus,
  mergeBoxRollupStatus,
  status,
  viewerCanAddAndRemoveFromMergeQueue,
  viewerCanAddToMergeQueueSolo,
  shouldFocusPrimaryMergeButton,
  setShouldFocusPrimaryMergeButton,
}: AddToMergeQueueSectionProps & MergeButtonFocusProps) {
  const mergeQueueUrl = mergeQueue?.url

  const [selectedMergeQueueOption, setSelectedMergeQueueOption] = useState<MergeQueueMethod>(MergeQueueMethod.GROUP)
  const [showConfirmMergeWhenReady, setShowConfirmMergeWhenReady] = useState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string>()
  const {sendAnalyticsEvent} = useAnalytics()

  const {mutate: enableAutoMerge, isPending} = useEnableAutoMergeMutation({
    onError: (e: Error) => {
      setErrorMessage(e.message)
    },
  })

  const enqueuePullRequest = () => {
    setShowConfirmMergeWhenReady(true)
    // TODO: remove "?." when :merge_box_hide_sections Feature Flag is removed
    handleConfirmingMergeInfo?.(true)
    sendAnalyticsEvent('auto_merge_section.merge_click', 'MERGEBOX_AUTO_MERGE_BUTTON')
  }

  const createAutoMergeRequest = () => {
    if (isPending) return

    setErrorMessage(undefined)

    // todo: add jump method along with permission checks for each option
    const mergeQueueMethod = selectedMergeQueueOption === MergeQueueMethod.SOLO ? 'SOLO' : 'GROUP'
    enableAutoMerge({mergeMethod: mergeQueueMethod})
    handleConfirmingMergeInfo?.(false)
    sendAnalyticsEvent('auto_merge_section.confirm_direct_merge', 'MERGEBOX_AUTO_MERGE_CONFIRMATION_BUTTON')
  }

  const updateMergeQueueMethod = (newMergeQueueMethod: MergeQueueMethod, analyticsEvent: string) => {
    setSelectedMergeQueueOption(newMergeQueueMethod)
    sendAnalyticsEvent(analyticsEvent, 'MERGEBOX_MERGE_QUEUE_SECTION_MERGE_METHOD_MENU_ITEM')
  }

  const isMergeable = calculateMergeability(mergeRequirementsState, status, mergeStateStatus)
  const mergeWhenReadyDisabled =
    !viewerCanAddAndRemoveFromMergeQueue ||
    mergeStateStatus === 'UNKNOWN' ||
    isDraft ||
    isInMergeQueue ||
    !!autoMergeRequest

  const defaultBranchName = baseRefName

  const mergeButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (showConfirmMergeWhenReady && mergeButtonRef?.current) {
      mergeButtonRef?.current.focus()
    }
  }, [showConfirmMergeWhenReady])

  return (
    <>
      {errorMessage && (
        <Flash className="mb-3" variant="danger">
          <Octicon className="mr-2" icon={StopIcon} />
          {errorMessage}
        </Flash>
      )}
      {showConfirmMergeWhenReady ? (
        <MergeSectionActions>
          <MergeSectionActions.Slot>
            <Button
              ref={mergeButtonRef}
              variant="primary"
              loading={isPending}
              loadingAnnouncement={mergeQueueButtonText({
                mergeMethod: selectedMergeQueueOption,
                confirming: true,
                inProgress: true,
              })}
              onClick={createAutoMergeRequest}
            >
              {mergeQueueButtonText({
                mergeMethod: selectedMergeQueueOption,
                confirming: true,
                inProgress: false,
              })}
            </Button>
          </MergeSectionActions.Slot>
          <MergeSectionActions.Slot>
            <Button
              onClick={() => {
                handleConfirmingMergeInfo?.(false)
                setShowConfirmMergeWhenReady(false)
                sendAnalyticsEvent(
                  'auto_merge_section.cancel_auto_merge',
                  'MERGEBOX_AUTO_MERGE_CANCEL_CONFIRMATION_BUTTON',
                )
              }}
            >
              Cancel
            </Button>
          </MergeSectionActions.Slot>
        </MergeSectionActions>
      ) : (
        <MergeSectionActions>
          <MergeSectionActions.Slot>
            <ButtonWithDropdown
              inactive={mergeWhenReadyDisabled}
              inactiveTooltipText={
                mergeRequirementsState === 'UNKNOWN'
                  ? 'Checking for the ability to merge automatically'
                  : 'Merging is blocked due to failing merge requirements'
              }
              inactiveTooltipDirection="se"
              // We hide the secondary button and its actions if the viewer can only merge in a group
              hideSecondaryButton={!viewerCanAddToMergeQueueSolo}
              secondaryButtonAriaLabel="Select merge queue method"
              isPrimary={isMergeable && mergeBoxRollupStatus === 'ALL_PASSED'}
              shouldFocusPrimaryButton={shouldFocusPrimaryMergeButton}
              onFocusPrimaryButton={() => setShouldFocusPrimaryMergeButton(false)}
              actionList={
                <ActionList selectionVariant="single">
                  <>
                    <MergeDropdownOption
                      primaryText="Queue and merge in a group"
                      secondaryText={`This pull request will be automatically grouped with other pull requests and merged into ${defaultBranchName}.`}
                      selected={selectedMergeQueueOption === MergeQueueMethod.GROUP}
                      onSelect={() =>
                        updateMergeQueueMethod(
                          MergeQueueMethod.GROUP,
                          'merqe_queue_section.select_queue_and_merge_in_a_group',
                        )
                      }
                    />
                    <MergeDropdownOption
                      primaryText="Queue and force solo merge"
                      secondaryText={`This pull request will be merged into ${defaultBranchName} by itself.`}
                      selected={selectedMergeQueueOption === MergeQueueMethod.SOLO}
                      onSelect={() =>
                        updateMergeQueueMethod(
                          MergeQueueMethod.SOLO,
                          'merqe_queue_section.select_queue_and_force_solo_merge',
                        )
                      }
                    />
                  </>
                </ActionList>
              }
              onPrimaryButtonClick={enqueuePullRequest}
            >
              {mergeQueueButtonText({
                mergeMethod: selectedMergeQueueOption,
                confirming: false,
                inProgress: isPending,
              })}
            </ButtonWithDropdown>
          </MergeSectionActions.Slot>
          <MergeSectionActions.Slot>
            <span className="f6 fgColor-muted pl-2">
              This repository uses the{' '}
              <Link href={mergeQueueUrl} inline>
                merge queue
              </Link>{' '}
              for all merges into the {defaultBranchName} branch.
            </span>
          </MergeSectionActions.Slot>
        </MergeSectionActions>
      )}
    </>
  )
}

type DisableAutoMergeProps = {
  autoMergeRequest: AutoMergeRequest
  isMergeQueueEnabled?: boolean
  viewerCanDisableAutoMerge: boolean
  handleConfirmingMergeInfo: (isConfirming: boolean) => void
}

/**
 * Renders the "disable auto merge" button when auto merge is currently enabled but the PR hasn't merged or been
 * added to the merge queue yet
 */
function DisableAutoMerge({
  autoMergeRequest,
  viewerCanDisableAutoMerge,
  isMergeQueueEnabled,
  handleConfirmingMergeInfo,
}: DisableAutoMergeProps) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [errorMessage, setErrorMessage] = useSafeState<string | undefined>()

  const {mutate: disableAutoMerge, isPending} = useDisableAutoMergeMutation({
    onError: (e: Error) => {
      setErrorMessage(e.message)
    },
  })

  const handleDisableAutoMerge = () => {
    if (isPending) return
    setErrorMessage(undefined)
    handleConfirmingMergeInfo(false)
    disableAutoMerge()
    sendAnalyticsEvent('auto_merge_section.disable_auto_merge', 'MERGEBOX_AUTO_MERGE_DISABLE_BUTTON')
  }

  const autoMergeVerb = autoMergeRequest?.mergeMethod.toLowerCase() ?? 'merge'
  const autoMergeMessage = isMergeQueueEnabled ? 'be added to the merge queue' : `${autoMergeVerb} automatically`

  return (
    <>
      {errorMessage && (
        <Flash className="mx-3 my-2" variant="danger">
          <Octicon className="mr-2" icon={StopIcon} />
          {errorMessage}
        </Flash>
      )}
      <MergeSectionActions>
        <MergeSectionActions.Slot>
          <Button
            disabled={!viewerCanDisableAutoMerge}
            onClick={handleDisableAutoMerge}
            loading={isPending}
            loadingAnnouncement="Disabling auto-merge"
          >
            Disable auto-merge
          </Button>
        </MergeSectionActions.Slot>
        <MergeSectionActions.Slot>
          <div className="flex-1">
            This pull request will <span className="text-semibold">{autoMergeMessage}</span> when all requirements are
            met.{' '}
            <Link inline href={AUTOMERGE_DOCS_LINK}>
              Learn more about automatically merging a pull request.
            </Link>
          </div>
        </MergeSectionActions.Slot>
      </MergeSectionActions>
    </>
  )
}

export type MergeSectionProps = {
  advisoryWorkspace: AdvisoryWorkspace
  autoMergeRequest: AutoMergeRequest
  baseRefName: string
  canUserPushToBase: boolean
  defaultCommitAuthorEmail: PullRequestMergeRequirementsPayload['defaultCommitAuthorEmail']
  commitMessageBody: PullRequestMergeRequirementsPayload['commitMessageBody']
  commitMessageHeadline: PullRequestMergeRequirementsPayload['commitMessageHeadline']
  conflictsCondition: DirectMergeActionsSectionProps['conflictsCondition']
  // TODO: remove "?" when :merge_box_hide_sections Feature Flag is removed
  handleConfirmingMergeInfo?: (isConfirming: boolean) => void
  headRepository: {ownerLogin: string; name: string} | null
  helpUrl: string
  id: string
  isDraft: boolean
  // TODO: remove "?" when :merge_box_hide_sections Feature Flag is removed
  isConfirmingMergeInfo?: boolean
  isCrossRepo: boolean
  isInMergeQueue: boolean
  mergeBoxRollupStatus: MergeBoxRollupStatus
  mergeQueue: MergeQueue
  mergeRequirementsState: PullRequestMergeRequirementsState
  mergeStateStatus: MergeStateStatus
  numberOfCommits: number
  status: Status
  viewerCanAddAndRemoveFromMergeQueue: JSONAPIPullRequestPayload['viewerCanAddAndRemoveFromMergeQueue']
  viewerCanAddToMergeQueueSolo: JSONAPIPullRequestPayload['viewerCanAddToMergeQueueSolo']
  viewerCanAdminBypassMergeRequirements: boolean
  viewerCanDisableAutoMerge: JSONAPIPullRequestPayload['viewerCanDisableAutoMerge']
  viewerCanEnableAutoMerge: JSONAPIPullRequestPayload['viewerCanEnableAutoMerge']
  viewerMergeActions: ViewerMergeActions
  possibleCommitAuthorEmails: PullRequestMergeRequirementsPayload['possibleCommitAuthorEmails']
} & MergeButtonFocusProps

/**
 * Renders the merge actions section of the merge box, specifically the merge button
 * Depending on configurations, a viewer can select a merge method, merge directly, or add the pull request to the merge queue
 */
export function MergeSection({
  advisoryWorkspace,
  autoMergeRequest,
  handleConfirmingMergeInfo,
  id,
  isConfirmingMergeInfo,
  isInMergeQueue,
  mergeQueue,
  mergeStateStatus,
  viewerCanAddAndRemoveFromMergeQueue,
  viewerCanAddToMergeQueueSolo,
  viewerCanDisableAutoMerge,
  viewerCanEnableAutoMerge,
  viewerCanAdminBypassMergeRequirements,
  ...rest
}: MergeSectionProps & MergeButtonFocusProps) {
  const [isAdminBypassToggleChecked, setIsAdminBypassToggleChecked] = useState(false)
  // TODO: remove this state when :merge_box_hide_sections Feature Flag is removed
  const [isConfirmingSelectedMerge, setIsConfirmingSelectedMerge] = useState(false)
  const viewerMergeActions = rest.viewerMergeActions
  const mergeQueueMergeAction = viewerMergeActions.find(({name}) => name === MergeAction.MERGE_QUEUE)
  const directMergeAction = viewerMergeActions.find(action => action.name === MergeAction.DIRECT_MERGE)

  const isMergeable = calculateMergeability(rest.mergeRequirementsState, rest.status, mergeStateStatus)
  const isMergeQueueEnabled = mergeQueueMergeAction?.isAllowable
  const isDirectMergeEnabled = directMergeAction?.isAllowable
  const isAutoMergeActive = !!autoMergeRequest

  // If an AutoMerge request is present, we do not show the bypass checkbox.
  // When merge queue is enabled, the ability to bypass the merge requirements does not depend on mergeability state.
  // We check for mergeability, for cases where mergeability is dependent on Status Checks
  // and the checkbox should respond to live updates of Status Checks
  const showAllowableToBypass =
    viewerCanAdminBypassMergeRequirements && !isAutoMergeActive && (!!isMergeQueueEnabled || !isMergeable)
  // We check for mergeability, for cases where mergeability is dependent on Status Checks
  // and the checkbox should respond to live updates of Status Checks
  const showIsAutoMerge = viewerCanEnableAutoMerge && !isMergeable
  // don't render if in an advisoryWorkspace
  if (advisoryWorkspace) return null

  let mergeComponent
  if (isAutoMergeActive) {
    // Auto merge is enabled because a request is present
    mergeComponent = (
      <DisableAutoMerge
        autoMergeRequest={autoMergeRequest}
        isMergeQueueEnabled={isMergeQueueEnabled}
        viewerCanDisableAutoMerge={viewerCanDisableAutoMerge}
        handleConfirmingMergeInfo={handleConfirmingMergeInfo ?? setIsConfirmingSelectedMerge}
      />
    )
  } else if (!isMergeQueueEnabled && !isDirectMergeEnabled) {
    // Inactive state
    mergeComponent = (
      <DirectMergeActionsSection
        mergeable={false}
        // TODO: only use handleConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        handleConfirmingMergeInfo={handleConfirmingMergeInfo ?? setIsConfirmingSelectedMerge}
        isAdminBypassToggleChecked={false}
        isAdminBypassToggleVisible={false}
        // TODO: only use isConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        isConfirmingMergeInfo={isConfirmingMergeInfo ?? isConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else if (isMergeQueueEnabled && showAllowableToBypass && isAdminBypassToggleChecked) {
    // Merge queue is enabled, but the user can bypass merge queue and did bypass merge queue, so we let them direct merge
    mergeComponent = (
      <DirectMergeActionsSection
        mergeable={isMergeable}
        // TODO: only use handleConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        handleConfirmingMergeInfo={handleConfirmingMergeInfo ?? setIsConfirmingSelectedMerge}
        isAdminBypassToggleVisible={showAllowableToBypass}
        isAdminBypassToggleChecked
        // TODO: only use isConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        isConfirmingMergeInfo={isConfirmingMergeInfo ?? isConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else if (isMergeQueueEnabled) {
    // Merge queue is enabled but the user hasn't elected to bypass it (or possibly cannot bypass it)
    mergeComponent = (
      <AddToMergeQueueSection
        autoMergeRequest={autoMergeRequest}
        pullRequestId={id}
        handleConfirmingMergeInfo={handleConfirmingMergeInfo}
        isInMergeQueue={isInMergeQueue}
        mergeQueue={mergeQueue}
        mergeStateStatus={mergeStateStatus}
        viewerCanAddAndRemoveFromMergeQueue={viewerCanAddAndRemoveFromMergeQueue}
        viewerCanAddToMergeQueueSolo={viewerCanAddToMergeQueueSolo}
        {...rest}
      />
    )
  } else if (viewerCanEnableAutoMerge && !isAdminBypassToggleChecked) {
    // Auto merge is allowed and the user hasn't bypassed it to direct merge
    mergeComponent = (
      <DirectMergeActionsSection
        // TODO: only use handleConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        handleConfirmingMergeInfo={handleConfirmingMergeInfo ?? setIsConfirmingSelectedMerge}
        mergeable={isMergeable}
        isAdminBypassToggleChecked={false}
        isAdminBypassToggleVisible={showAllowableToBypass}
        isAutoMergeAllowed={showIsAutoMerge}
        // TODO: only use isConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        isConfirmingMergeInfo={isConfirmingMergeInfo ?? isConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else {
    mergeComponent = (
      <DirectMergeActionsSection
        // TODO: only use handleConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        handleConfirmingMergeInfo={handleConfirmingMergeInfo ?? setIsConfirmingSelectedMerge}
        isAdminBypassToggleChecked={isAdminBypassToggleChecked}
        isAdminBypassToggleVisible={showAllowableToBypass}
        // TODO: only use isConfirmingMergeInfo when :merge_box_hide_sections Feature Flag is removed
        isConfirmingMergeInfo={isConfirmingMergeInfo ?? isConfirmingSelectedMerge}
        mergeable={isMergeable}
        {...rest}
      />
    )
  }

  return (
    <div
      className={clsx('p-3 bgColor-muted borderColor-muted', isConfirmingMergeInfo ? 'rounded-2' : 'rounded-bottom-2')}
    >
      {/** TODO: adjust logic when :merge_box_hide_sections Feature Flag is removed */}
      {showAllowableToBypass && !isConfirmingMergeInfo && !isConfirmingSelectedMerge && (
        <div className="mb-3">
          <BypassMergeRequirementsToggle
            checked={isAdminBypassToggleChecked}
            onToggleChecked={() => setIsAdminBypassToggleChecked(!isAdminBypassToggleChecked)}
          />
        </div>
      )}
      {mergeComponent}
    </div>
  )
}
