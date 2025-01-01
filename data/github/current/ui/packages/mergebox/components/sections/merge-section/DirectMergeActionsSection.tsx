import {assertDataPresent} from '@github-ui/assert-data-present'
import {useAnalytics} from '@github-ui/use-analytics'
import {ActionList, Link} from '@primer/react'
import {lazy, Suspense, useRef, useState} from 'react'

import {useMergeMethodContext} from '../../../contexts/MergeMethodContext'
import {mergeButtonText} from '../../../helpers/merge-button-text'
import {
  MergeMethod,
  MergeAction,
  type ViewerMergeActions,
  type ViewerMergeMethods,
  type PullRequestMergeConditionResult,
} from '../../../types'
import {ConfirmMerge} from '../../ConfirmMerge'
import {ButtonWithDropdown} from '../common/ButtonWithDropdown'
import {MergeDropdownOption} from './MergeDropdownOption'
import type {PullRequestMergeRequirementsPayload} from '../../../page-data/payloads/merge-box'
import {Status} from '../../../helpers/mergeability-status'
import {MergeSectionActions} from './MergeSectionActions'
import useSafeState from '@github-ui/use-safe-state'

const CommandLineInstructionsDialog = lazy(() => import('./command-line-instructions/CommandLineInstructionsDialog'))

/**
 * Return a list of merge methods to show in the "select merge method" dropdown
 */
export function allowableMergeMethods({
  mergeMethods,
  bypassableOnly = false,
}: {
  mergeMethods: ViewerMergeMethods
  bypassableOnly?: boolean
}): MergeMethod[] {
  return mergeMethods.reduce<MergeMethod[]>((allowedMergeMethods, method) => {
    if ((!bypassableOnly && method?.isAllowable) || method?.isAllowableWithBypass) {
      allowedMergeMethods.push(method.name as MergeMethod)
    }

    return allowedMergeMethods
  }, [])
}

export type MergeButtonFocusProps = {
  shouldFocusPrimaryMergeButton: boolean
  setShouldFocusPrimaryMergeButton: (shouldFocus: boolean) => void
}

export type Props = {
  baseRefName: string
  canUserPushToBase: boolean
  commitAuthorEmail: PullRequestMergeRequirementsPayload['commitAuthorEmail']
  commitMessageBody: PullRequestMergeRequirementsPayload['commitMessageBody']
  commitMessageHeadline: PullRequestMergeRequirementsPayload['commitMessageHeadline']
  conflictsCondition: {result: PullRequestMergeConditionResult} | undefined
  headRepository: {ownerLogin: string; name: string} | null
  helpUrl: string
  isAdminBypassToggleChecked: boolean
  isAdminBypassToggleVisible: boolean
  isAutoMergeAllowed?: boolean
  isCrossRepo: boolean
  isDraft: boolean
  mergeRequirementsState: PullRequestMergeRequirementsPayload['state']
  mergeable: boolean
  numberOfCommits: number
  onIsConfirmingSelectedMerge: (isConfirming: boolean) => void
  status: Status
  viewerMergeActions: ViewerMergeActions
} & MergeButtonFocusProps

/**
 * Renders the merge button and provides the ability to select from the available merge methods
 */
export function DirectMergeActionsSection({
  baseRefName,
  canUserPushToBase,
  commitAuthorEmail,
  commitMessageBody,
  commitMessageHeadline,
  conflictsCondition,
  headRepository,
  helpUrl,
  isAdminBypassToggleChecked,
  isAdminBypassToggleVisible,
  isAutoMergeAllowed = false,
  isCrossRepo,
  mergeable,
  numberOfCommits,
  onIsConfirmingSelectedMerge,
  setShouldFocusPrimaryMergeButton,
  shouldFocusPrimaryMergeButton,
  status,
  viewerMergeActions,
}: Props) {
  const {mergeMethod, setMergeMethod} = useMergeMethodContext()
  const {sendAnalyticsEvent} = useAnalytics()

  const [isConfirmingSelectedMerge, setIsConfirmingSelectedMerge] = useState(false)
  const [isCommandLineInstructionsOpen, setIsCommandLineInstructionsOpen] = useSafeState(false)
  const returnFocusToCommandLineInstructionsButtonRef = useRef<HTMLButtonElement | null>(null)

  // TODO: Allow ability to select from possible commit emails

  if (!conflictsCondition) return null
  const directMergeAction = viewerMergeActions.find(action => action.name === MergeAction.DIRECT_MERGE)
  assertDataPresent(directMergeAction)

  const allowedMergeMethods = allowableMergeMethods({mergeMethods: directMergeAction.mergeMethods})
  const canCreateMergeCommit = allowedMergeMethods.includes(MergeMethod.MERGE)
  const canSquashMerge = allowedMergeMethods.includes(MergeMethod.SQUASH)
  const canRebaseMerge = allowedMergeMethods.includes(MergeMethod.REBASE)

  // account for a scenario where the button is checked, then a live update causes the PR's state to update to
  // be mergeable and we stop showing the checkbox
  const isBypassRulesActive = isAdminBypassToggleVisible && isAdminBypassToggleChecked

  const inactiveTooltipTextVerb = status === Status.ChecksPending ? 'pending' : 'failing'
  const inactiveTooltipText = `Merging is blocked due to ${inactiveTooltipTextVerb} merge requirements`

  const confirmMerge = () => {
    setIsConfirmingSelectedMerge(true)
    onIsConfirmingSelectedMerge(true)
    const analyticsEventKey = isAutoMergeAllowed
      ? 'direct_merge_section.auto_merge_click'
      : 'direct_merge_section.direct_merge_click'

    const analyticsEventValue = isAutoMergeAllowed
      ? 'MERGEBOX_AUTO_MERGE_SECTION_MERGE_BUTTON'
      : 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_BUTTON'

    sendAnalyticsEvent(analyticsEventKey, analyticsEventValue)
  }

  const cancelMerge = () => {
    setIsConfirmingSelectedMerge(false)
    onIsConfirmingSelectedMerge(false)
    setShouldFocusPrimaryMergeButton(true)

    const analyticsEventKey = isAutoMergeAllowed
      ? 'direct_merge_section.cancel_auto_merge'
      : 'direct_merge_section.cancel_direct_merge'

    const analyticsEventValue = isAutoMergeAllowed
      ? 'MERGEBOX_AUTO_MERGE_CANCEL_CONFIRMATION_BUTTON'
      : 'MERGEBOX_DIRECT_MERGE_CANCEL_CONFIRMATION_BUTTON'

    sendAnalyticsEvent(analyticsEventKey, analyticsEventValue)
  }

  const handleOpenCommandLineInstructions = () => {
    setIsCommandLineInstructionsOpen(true)
    sendAnalyticsEvent(
      'direct_merge_section.view_command_line_instructions',
      'MERGEBOX_DIRECT_MERGE_SECTION_VIEW_COMMAND_LINE_INSTRUCTIONS_BUTTON',
    )
  }

  const updateMergeMethod = (newMergeMethod: MergeMethod, analyticsEvent: string) => {
    setMergeMethod(newMergeMethod)
    sendAnalyticsEvent(analyticsEvent, 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_METHOD_MENU_ITEM')
  }

  if (isConfirmingSelectedMerge) {
    return (
      <ConfirmMerge
        commitAuthorEmail={commitAuthorEmail || ''}
        commitMessageBody={commitMessageBody || ''}
        commitMessageHeadline={commitMessageHeadline || ''}
        defaultBranchName={baseRefName}
        isBypassMerge={isAdminBypassToggleChecked}
        selectedMergeMethod={mergeMethod}
        onCancel={cancelMerge}
        isAutoMergeAllowed={isAutoMergeAllowed}
      />
    )
  }

  return (
    <>
      {isCommandLineInstructionsOpen && returnFocusToCommandLineInstructionsButtonRef && (
        // Wrap this in a Suspense boundary so that we can lazy load the dialog without disrupting the rest of the merge box
        <Suspense>
          <CommandLineInstructionsDialog
            baseRefName={baseRefName}
            conflictsCondition={conflictsCondition}
            headRepository={headRepository}
            isCrossRepo={isCrossRepo}
            returnFocusRef={returnFocusToCommandLineInstructionsButtonRef}
            onClose={() => setIsCommandLineInstructionsOpen(false)}
          />
        </Suspense>
      )}
      <MergeSectionActions>
        <MergeSectionActions.Slot>
          <ButtonWithDropdown
            hideSecondaryButton={allowedMergeMethods.length === 1}
            inactive={isAutoMergeAllowed ? false : !mergeable && !isBypassRulesActive}
            inactiveTooltipText={inactiveTooltipText}
            inactiveTooltipDirection="se"
            isPrimary={mergeable && status !== Status.NonRequiredChecksUnsuccessful}
            secondaryButtonActive
            secondaryButtonAriaLabel="Select merge method"
            shouldFocusPrimaryButton={shouldFocusPrimaryMergeButton}
            actionList={
              <ActionList selectionVariant="single" showDividers>
                {canCreateMergeCommit && (
                  <MergeDropdownOption
                    primaryText="Create a merge commit"
                    secondaryText="All commits from this branch will be added to the base branch via a merge commit."
                    selected={mergeMethod === MergeMethod.MERGE}
                    onSelect={() =>
                      updateMergeMethod(MergeMethod.MERGE, 'direct_merge_section.select_create_a_merge_commit')
                    }
                  />
                )}
                {canSquashMerge && (
                  <MergeDropdownOption
                    primaryText="Squash and merge"
                    secondaryText={
                      numberOfCommits === 1
                        ? 'The 1 commit from this branch will be added to the base branch.'
                        : `The ${numberOfCommits} commits from this branch will be combined into one commit in the base branch.`
                    }
                    selected={mergeMethod === MergeMethod.SQUASH}
                    onSelect={() =>
                      updateMergeMethod(MergeMethod.SQUASH, 'direct_merge_section.select_squash_and_merge')
                    }
                  />
                )}
                {canRebaseMerge && (
                  <MergeDropdownOption
                    primaryText="Rebase and merge"
                    secondaryText={`The ${numberOfCommits} commit${
                      numberOfCommits !== 1 ? 's' : ''
                    } from this branch will be rebased and added to the base branch.`}
                    selected={mergeMethod === MergeMethod.REBASE}
                    onSelect={() =>
                      updateMergeMethod(MergeMethod.REBASE, 'direct_merge_section.select_rebase_and_merge')
                    }
                  />
                )}
              </ActionList>
            }
            onFocusPrimaryButton={() => setShouldFocusPrimaryMergeButton(false)}
            onPrimaryButtonClick={confirmMerge}
          >
            {mergeButtonText({
              mergeMethod,
              confirming: false,
              isBypassMerge: isBypassRulesActive,
              isAutoMergeAllowed,
            })}
          </ButtonWithDropdown>
        </MergeSectionActions.Slot>
        <MergeSectionActions.Slot>
          <span className="f6 fgColor-muted">
            {canUserPushToBase ? (
              <>
                You can also merge this with the command line, view{' '}
                <Link
                  as="button"
                  ref={returnFocusToCommandLineInstructionsButtonRef}
                  inline
                  onClick={handleOpenCommandLineInstructions}
                >
                  command line instructions
                </Link>
                .
              </>
            ) : (
              <>
                Only those with{' '}
                <Link href={`${helpUrl}/en/get-started/learning-about-github/access-permissions-on-github`} inline>
                  write access
                </Link>{' '}
                to this repository can merge pull requests.
              </>
            )}
          </span>
        </MergeSectionActions.Slot>
      </MergeSectionActions>
    </>
  )
}
