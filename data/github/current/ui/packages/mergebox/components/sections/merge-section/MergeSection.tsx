import {useAnalytics} from '@github-ui/use-analytics'
import {ActionList, Button, Flash, Link, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useEffect, useRef, useState} from 'react'
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
} from '../../../types'
import {useDisableAutoMergeMutation} from '../../../hooks/mutations/use-disable-auto-merge-mutation'
import {useEnableAutoMergeMutation} from '../../../hooks/mutations/use-enable-auto-merge-mutation'
import {BypassMergeRequirementsToggle} from './BypassMergeRequirementsToggle'
import type {
  PullRequestMergeRequirementsPayload,
  JSONAPIPullRequestPayload,
} from '../../../page-data/payloads/merge-box'
import {Status} from '../../../helpers/mergeability-status'
import useSafeState from '@github-ui/use-safe-state'
import {MergeSectionActions} from './MergeSectionActions'
import {calculateMergeability} from '../../../helpers/mergeability-helpers'
const AUTOMERGE_DOCS_LINK =
  'https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request'

export type AddToMergeQueueSectionProps = {
  autoMergeRequest: AutoMergeRequest
  baseRefName: string
  pullRequestId: string
  isDraft: boolean
  isInMergeQueue: boolean
  mergeQueue: MergeQueue
  mergeRequirementsState: PullRequestMergeRequirementsState
  mergeStateStatus: MergeStateStatus
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
  isDraft,
  isInMergeQueue,
  mergeQueue,
  mergeRequirementsState,
  mergeStateStatus,
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
    sendAnalyticsEvent('auto_merge_section.merge_click', 'MERGEBOX_AUTO_MERGE_BUTTON')
  }

  const createAutoMergeRequest = () => {
    if (isPending) return

    setErrorMessage(undefined)

    // todo: add jump method along with permission checks for each option
    const mergeQueueMethod = selectedMergeQueueOption === MergeQueueMethod.SOLO ? 'SOLO' : 'GROUP'
    enableAutoMerge({mergeMethod: mergeQueueMethod})
    sendAnalyticsEvent('auto_merge_section.confirm_direct_merge', 'MERGEBOX_AUTO_MERGE_CONFIRMATION_BUTTON')
  }

  const updateMergeQueueMethod = (newMergeQueueMethod: MergeQueueMethod, analyticsEvent: string) => {
    setSelectedMergeQueueOption(newMergeQueueMethod)
    sendAnalyticsEvent(analyticsEvent, 'MERGEBOX_MERGE_QUEUE_SECTION_MERGE_METHOD_MENU_ITEM')
  }

  const isMergeable = calculateMergeability(mergeRequirementsState, status)
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
              aria-disabled={isPending}
              inactive={isPending}
              variant="primary"
              onClick={createAutoMergeRequest}
            >
              <div className="d-flex flex-items-center flex-row">
                {mergeQueueButtonText({
                  mergeMethod: selectedMergeQueueOption,
                  confirming: true,
                  inProgress: isPending,
                })}
                {isPending && <Spinner size="small" sx={{ml: 2}} />}
              </div>
            </Button>
          </MergeSectionActions.Slot>
          <MergeSectionActions.Slot>
            <Button
              onClick={() => {
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
              inactiveTooltipText="Merging is blocked due to failing merge requirements"
              inactiveTooltipDirection="se"
              // We hide the secondary button and it's actions if the viewer can only merge in a group
              hideSecondaryButton={!viewerCanAddToMergeQueueSolo}
              secondaryButtonAriaLabel="Select merge queue method"
              isPrimary={isMergeable && status !== Status.NonRequiredChecksUnsuccessful}
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
}

/**
 * Renders the "disable auto merge" button when auto merge is currently enabled but the PR hasn't merged or been
 * added to the merge queue yet
 */
function DisableAutoMerge({autoMergeRequest, viewerCanDisableAutoMerge, isMergeQueueEnabled}: DisableAutoMergeProps) {
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
            aria-disabled={isPending}
            disabled={!viewerCanDisableAutoMerge}
            onClick={handleDisableAutoMerge}
            inactive={isPending}
          >
            <div className="d-flex flex-items-center flex-row">
              {isPending ? 'Disabling auto-merge...' : 'Disable auto-merge'}
              {isPending && <Spinner size="small" sx={{ml: 2}} />}
            </div>
          </Button>
        </MergeSectionActions.Slot>
        <MergeSectionActions.Slot>
          <div>
            This pull request will <span className="text-semibold">{autoMergeMessage}</span> when all requirements are
            met.{' '}
            <Link inline href={AUTOMERGE_DOCS_LINK}>
              Learn more.
            </Link>
          </div>
        </MergeSectionActions.Slot>
      </MergeSectionActions>
    </>
  )
}

export type MergeSectionProps = {
  autoMergeRequest: AutoMergeRequest
  baseRefName: string
  canUserPushToBase: boolean
  commitAuthorEmail: PullRequestMergeRequirementsPayload['commitAuthorEmail']
  commitMessageBody: PullRequestMergeRequirementsPayload['commitMessageBody']
  commitMessageHeadline: PullRequestMergeRequirementsPayload['commitMessageHeadline']
  conflictsCondition: DirectMergeActionsSectionProps['conflictsCondition']
  headRepository: {ownerLogin: string; name: string} | null
  helpUrl: string
  id: string
  isDraft: boolean
  isCrossRepo: boolean
  isInMergeQueue: boolean
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
} & MergeButtonFocusProps

/**
 * Renders the merge actions section of the merge box, specifically the merge button
 * Depending on configurations, a viewer can select a merge method, merge directly, or add the pull request to the merge queue
 */
export function MergeSection({
  autoMergeRequest,
  id,
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
  const [isConfirmingSelectedMerge, setIsConfirmingSelectedMerge] = useState(false)
  const viewerMergeActions = rest.viewerMergeActions
  const mergeQueueMergeAction = viewerMergeActions.find(({name}) => name === MergeAction.MERGE_QUEUE)
  const directMergeAction = viewerMergeActions.find(action => action.name === MergeAction.DIRECT_MERGE)

  const isMergeable = calculateMergeability(rest.mergeRequirementsState, rest.status)
  const isMergeQueueEnabled = mergeQueueMergeAction?.isAllowable
  const isDirectMergeEnabled = directMergeAction?.isAllowable
  const isAutoMergeActive = !!autoMergeRequest
  const showAllowableToBypass = !isMergeable && viewerCanAdminBypassMergeRequirements

  let mergeComponent
  if (isAutoMergeActive) {
    // Auto merge is enabled because a request is present
    mergeComponent = (
      <DisableAutoMerge
        autoMergeRequest={autoMergeRequest}
        isMergeQueueEnabled={isMergeQueueEnabled}
        viewerCanDisableAutoMerge={viewerCanDisableAutoMerge}
      />
    )
  } else if (!isMergeQueueEnabled && !isDirectMergeEnabled) {
    // Inactive state
    mergeComponent = (
      <DirectMergeActionsSection
        mergeable={false}
        isAdminBypassToggleChecked={false}
        isAdminBypassToggleVisible={false}
        onIsConfirmingSelectedMerge={setIsConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else if (isMergeQueueEnabled && showAllowableToBypass && isAdminBypassToggleChecked) {
    // Merge queue is enabled, but the user can bypass merge queue and did bypass merge queue, so we let them direct merge
    mergeComponent = (
      <DirectMergeActionsSection
        mergeable={isMergeable}
        isAdminBypassToggleVisible={showAllowableToBypass}
        isAdminBypassToggleChecked
        onIsConfirmingSelectedMerge={setIsConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else if (isMergeQueueEnabled) {
    // Merge queue is enabled but the user hasn't elected to bypass it (or possibly cannot bypass it)
    mergeComponent = (
      <AddToMergeQueueSection
        autoMergeRequest={autoMergeRequest}
        pullRequestId={id}
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
        isAutoMergeAllowed
        mergeable={isMergeable}
        isAdminBypassToggleChecked={false}
        isAdminBypassToggleVisible={showAllowableToBypass}
        onIsConfirmingSelectedMerge={setIsConfirmingSelectedMerge}
        {...rest}
      />
    )
  } else {
    mergeComponent = (
      <DirectMergeActionsSection
        mergeable={isMergeable}
        isAdminBypassToggleChecked={isAdminBypassToggleChecked}
        isAdminBypassToggleVisible={showAllowableToBypass}
        onIsConfirmingSelectedMerge={setIsConfirmingSelectedMerge}
        {...rest}
      />
    )
  }

  return (
    <div className="p-3 bgColor-muted borderColor-muted rounded-bottom-2">
      {showAllowableToBypass && !isConfirmingSelectedMerge && (
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
