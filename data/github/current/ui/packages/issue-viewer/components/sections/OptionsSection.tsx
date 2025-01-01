import {ArrowRightIcon, LockIcon, TrashIcon, PinIcon, PinSlashIcon, CommentDiscussionIcon} from '@primer/octicons-react'
import {ActionList, CounterLabel, Heading} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {graphql} from 'relay-runtime'
import {useFragment, useRelayEnvironment} from 'react-relay'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {OptionConfig} from '../../components/OptionConfig'
import {BUTTON_LABELS} from '../../constants/buttons'
import {LABELS} from '../../constants/labels'
import type {OptionsSectionFragment$key} from './__generated__/OptionsSectionFragment.graphql'
import {IssueDeletionConfirmationDialog} from '../header/IssueDeletionConfirmationDialog'
import {useCallback, useState} from 'react'
import {IssueConversationLock} from '../header/IssueConversationLock'
import {IssueTransferDialog} from '../header/IssueTransferDialog'
import {ConvertToDiscussionDialog} from '../ConvertToDiscussionDialog'
import {commitUnpinIssueMutation} from '../../mutations/unpin-issue'
import {commitPinIssueMutation} from '../../mutations/pin-issue'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '../../constants/errors'
import type {OptionsSectionSecondary$key} from './__generated__/OptionsSectionSecondary.graphql'
import styles from './OptionsSection.module.css'
import {clsx} from 'clsx'

const PINNED_ISSUES_LIMIT = 3

const OptionsSectionFragment = graphql`
  fragment OptionsSectionFragment on Issue {
    id
    isPinned
    locked
    viewerCanDelete
    viewerCanTransfer
    viewerCanConvertToDiscussion
    viewerCanLock
    repository {
      id
      name
      owner {
        login
      }
      visibility
      pinnedIssues(first: 3) {
        totalCount
      }
      viewerCanPinIssues
    }
  }
`

export type OptionsSectionProps = {
  optionsSection: OptionsSectionFragment$key
  optionsSectionSecondary?: OptionsSectionSecondary$key | null
  optionConfig: OptionConfig
}

export function OptionsSection({optionsSection, optionsSectionSecondary, optionConfig}: OptionsSectionProps) {
  const [showIssueTransferDialog, setShowIssueTransferDialog] = useState(false)
  const [showConvertToDiscussionDialog, setShowConvertToDiscussionDialog] = useState(false)
  const [showIssueDeletionConfirmationDialog, setShowIssueDeletionConfirmationDialog] = useState(false)
  const [showConversationLockDialog, setShowConversationLockDialog] = useState(false)

  const {
    id,
    viewerCanLock,
    viewerCanTransfer,
    viewerCanDelete,
    viewerCanConvertToDiscussion,
    isPinned,
    locked,
    repository,
  } = useFragment(OptionsSectionFragment, optionsSection)

  const secondaryData = useFragment(
    graphql`
      fragment OptionsSectionSecondary on Issue {
        isTransferInProgress
      }
    `,
    optionsSectionSecondary,
  )

  // If the secondary data is not available, we default to false
  const isTransferInProgress = secondaryData?.isTransferInProgress ?? false

  const viewerCanPin = repository.viewerCanPinIssues

  const pinnedIssuesCount = repository?.pinnedIssues?.totalCount || 0

  const canPinNewIssue = pinnedIssuesCount < 3

  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const pinUnpin = useCallback(() => {
    if (!viewerCanPin) return

    if (isPinned) {
      commitUnpinIssueMutation({
        environment,
        input: {issueId: id},
        onCompleted: () => {},
        onError: () => {},
      })
    } else {
      if (canPinNewIssue) {
        commitPinIssueMutation({
          environment,
          input: {issueId: id},
          onCompleted: () => {},
          onError: () => {
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              type: 'error',
              message: ERRORS.couldNotUnpinIssue,
            })
          },
        })
      }
    }
  }, [addToast, canPinNewIssue, environment, id, isPinned, viewerCanPin])

  const disablePinningAction = !canPinNewIssue && !isPinned

  const primerReactFeatureFlag =
    isFeatureEnabled('primer_react_css_modules_staff') || isFeatureEnabled('primer_react_css_modules_ga')

  const classNames = primerReactFeatureFlag ? undefined : 'f6 py-1'

  return (
    <>
      <Heading as="h2" className="sr-only">
        {LABELS.optionsTitle}
      </Heading>

      {/* Note to maintainers: If adding support for new permissions, make sure `hideDivider` in the ParticipantsSection is updated too */}
      <ActionList variant="full" className={styles.ActionListOverrides}>
        {viewerCanTransfer && (
          <ActionList.Item onSelect={() => setShowIssueTransferDialog(true)} className={classNames}>
            <ActionList.LeadingVisual>
              <ArrowRightIcon />
            </ActionList.LeadingVisual>
            {BUTTON_LABELS.transferIssue}
          </ActionList.Item>
        )}

        {viewerCanLock && (
          <ActionList.Item onSelect={() => setShowConversationLockDialog(true)} className={classNames}>
            <ActionList.LeadingVisual>
              <LockIcon />
            </ActionList.LeadingVisual>
            <span>{locked ? LABELS.lock.buttonConfirmUnlock : LABELS.lock.buttonConfirmLock}</span>
          </ActionList.Item>
        )}

        {viewerCanPin && (
          <ActionList.Item
            aria-disabled={disablePinningAction || undefined}
            onSelect={pinUnpin}
            className={clsx(disablePinningAction && styles.DisablePin, classNames)}
          >
            <ActionList.LeadingVisual>
              {isPinned ? (
                <PinSlashIcon className={clsx(disablePinningAction && styles.DisablePin)} />
              ) : (
                <PinIcon className={clsx(disablePinningAction && styles.DisablePin)} />
              )}
            </ActionList.LeadingVisual>
            <Tooltip
              direction="s"
              sx={{width: '100%'}}
              text={
                disablePinningAction
                  ? '3/3 issues already pinned. Unpin an issue to pin this one.'
                  : isPinned
                    ? LABELS.unpinIssueTooltip
                    : LABELS.pinIssueTooltip
              }
            >
              {isPinned ? BUTTON_LABELS.unpinIssue : BUTTON_LABELS.pinIssue}
            </Tooltip>
            {pinnedIssuesCount > 0 && (
              <ActionList.TrailingVisual>
                <CounterLabel>
                  {pinnedIssuesCount}/{PINNED_ISSUES_LIMIT}
                </CounterLabel>
              </ActionList.TrailingVisual>
            )}
          </ActionList.Item>
        )}

        {viewerCanConvertToDiscussion && (
          <ActionList.Item onSelect={() => setShowConvertToDiscussionDialog(true)} className={classNames}>
            <ActionList.LeadingVisual>
              <CommentDiscussionIcon />
            </ActionList.LeadingVisual>
            {BUTTON_LABELS.convertToDiscussion}
          </ActionList.Item>
        )}
        {viewerCanDelete && (
          <ActionList.Item
            variant="danger"
            onSelect={() => setShowIssueDeletionConfirmationDialog(true)}
            className={classNames}
          >
            <ActionList.LeadingVisual>
              <TrashIcon />
            </ActionList.LeadingVisual>
            {BUTTON_LABELS.deleteIssue}
          </ActionList.Item>
        )}
      </ActionList>
      {showIssueTransferDialog && (
        <IssueTransferDialog
          owner={repository.owner.login}
          repository={repository.name}
          currentRepoVisibility={repository.visibility}
          issueId={id}
          isTransferInProgress={isTransferInProgress}
          onClose={() => setShowIssueTransferDialog(false)}
        />
      )}
      {showConvertToDiscussionDialog && (
        <ConvertToDiscussionDialog
          owner={repository.owner.login}
          repository={repository.name}
          issueId={id}
          onClose={() => setShowConvertToDiscussionDialog(false)}
        />
      )}
      {showConversationLockDialog && (
        <IssueConversationLock issueId={id} isUnlocked={!locked} onClose={() => setShowConversationLockDialog(false)} />
      )}
      {showIssueDeletionConfirmationDialog && (
        <IssueDeletionConfirmationDialog
          issueId={id}
          onSuccessfulDeletion={optionConfig.onIssueDelete}
          afterDelete={optionConfig.navigateBack}
          onClose={() => setShowIssueDeletionConfirmationDialog(false)}
        />
      )}
    </>
  )
}
