import type {IssuePickerItem} from '@github-ui/item-picker/IssuePicker'
import {RepositoryAndIssuePicker} from '@github-ui/item-picker/RepositoryAndIssuePicker'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ArrowRightIcon, IssueClosedIcon, IssueReopenedIcon, SkipIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ButtonGroup, IconButton} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import type React from 'react'
import {useCallback, useEffect, useRef, useState} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'

import type {IssueActions$key} from './__generated__/IssueActions.graphql'
import type {IssueActionsState$key, IssueState, IssueStateReason} from './__generated__/IssueActionsState.graphql'
import {ERRORS} from './constants/errors'
import {LABELS} from './constants/labels'
import styles from './IssueActions.module.css'
import type {IssueClosedStateReason} from './mutations/__generated__/updateIssueStateMutationCloseMutation.graphql'
import {commitCloseIssueMutation, commitReopenIssueMutation} from './mutations/update-issue-state-mutation'

export type CloseButtonState = 'CLOSED' | 'OPEN' | 'NOT_PLANNED' | 'DUPLICATE'

type IssueActionsBaseProps = {
  onAction: () => void
  hasComment: boolean
  buttonSize?: 'small' | 'medium'
  disabled?: boolean
  closeButtonState: CloseButtonState
  setCloseButtonState: (state: CloseButtonState) => void
  viewerCanReopen?: boolean
  viewerCanClose?: boolean
}

type InternalIssueActionsProps = IssueActionsBaseProps & {
  actionStateRef: IssueActionsState$key
  buttonSize?: 'small' | 'medium'
}

type IssueActionsProps = IssueActionsBaseProps & {
  actionRef: IssueActions$key
}

export function IssueActions({actionRef, ...rest}: IssueActionsProps) {
  const action = useFragment(
    graphql`
      fragment IssueActions on Issue {
        ...IssueActionsState
      }
    `,
    actionRef,
  )

  return <IssueActionsInternal actionStateRef={action} {...rest} />
}

function IssueActionsInternal({
  actionStateRef,
  disabled = false,
  onAction,
  hasComment,
  viewerCanClose,
  viewerCanReopen,
  buttonSize,
  closeButtonState,
  setCloseButtonState,
}: InternalIssueActionsProps) {
  const {addToast} = useToastContext()
  const [duplicateIssue, setDuplicateIssue] = useState<IssuePickerItem | null>(null)
  const environment = useRelayEnvironment()

  const data = useFragment(
    graphql`
      fragment IssueActionsState on Issue {
        id
        state
        stateReason(enableDuplicate: true)
        repository {
          id
          nameWithOwner
          owner {
            login
          }
        }
      }
    `,
    actionStateRef,
  )

  const closeIssue = useCallback(
    (newStateReason: IssueClosedStateReason) => {
      if (data && data.id) {
        return commitCloseIssueMutation({
          environment,
          input: {
            issueId: data.id,
            newStateReason,
            duplicateIssue: duplicateIssue
              ? {
                  id: duplicateIssue.id,
                  number: duplicateIssue.number,
                  url: duplicateIssue.url,
                }
              : undefined,
          },
          onCompleted: () => {
            setDuplicateIssue(null)
          },
          onError: () =>
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              type: 'error',
              message: ERRORS.couldNotCloseIssue,
            }),
        })
      }
    },
    [data, environment, duplicateIssue, addToast],
  )

  const reopenIssue = useCallback(() => {
    if (data.id) {
      commitReopenIssueMutation({
        environment,
        input: {
          issueId: data.id,
        },
        onError: () =>
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotReOpenIssue,
          }),
      })
    }
  }, [data, environment, addToast])

  useEffect(
    () => setCloseButtonState(getInitialButtonState(data.state)),
    [data.state, data.stateReason, data.id, setCloseButtonState],
  )
  const [open, setOpen] = useState(false)

  const viewerCanChange = data.state === 'OPEN' ? viewerCanClose : viewerCanReopen

  const duplicateIssueSelected = useCallback(
    (issue: IssuePickerItem | null) => {
      setDuplicateIssue(issue)
      setPickerType(null)
      setCloseButtonState(issue ? 'DUPLICATE' : 'CLOSED')
    },
    [setCloseButtonState],
  )

  const [pickerType, setPickerType] = useState<'Issue' | 'Repository' | null>(null)
  const anchorRef = useRef(null)
  const returnFocusRef = useRef<HTMLAnchorElement>(null)
  const onPickerTypeChange = useCallback(
    (type: 'Issue' | 'Repository' | null) => {
      // When the picker is closed, focus the trigger
      if (type === null && returnFocusRef?.current) {
        returnFocusRef.current.focus()
      }

      setPickerType(type)
    },
    [setPickerType],
  )

  const actionMenuOpenChange = useCallback(
    (newValue: boolean) => {
      setOpen(newValue)
      if (newValue) {
        setPickerType(null)
      }
    },
    [setOpen, setPickerType],
  )

  return (
    <>
      <ButtonGroup className={styles.ButtonGroup}>
        <UpdateStateButton
          disabled={disabled}
          issueState={data.state}
          buttonState={closeButtonState}
          onClose={closeIssue}
          onReopen={reopenIssue}
          onAction={onAction}
          hasComment={hasComment}
          size={buttonSize}
          viewerCanReopen={viewerCanReopen}
          viewerCanClose={viewerCanClose}
          duplicateIssue={duplicateIssue ?? undefined}
        />
        <ActionMenu anchorRef={anchorRef} open={open} onOpenChange={actionMenuOpenChange}>
          <ActionMenu.Anchor>
            <IconButton
              icon={TriangleDownIcon}
              aria-label={LABELS.moreOptions}
              size={buttonSize}
              disabled={disabled || !viewerCanChange}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="medium">
            <UpdateStateButtonOptions
              buttonState={closeButtonState}
              setButtonState={setCloseButtonState}
              canClose={closeIssue !== undefined}
              canReopen={reopenIssue !== undefined}
              viewerCanClose={viewerCanClose}
              viewerCanReopen={viewerCanReopen}
              issueState={data.state}
              issueStateReason={data.stateReason}
              duplicateIssueSelected={duplicateIssueSelected}
              setIsDuplicateDialogOpen={() => setPickerType('Issue')}
            />
          </ActionMenu.Overlay>
        </ActionMenu>
      </ButtonGroup>
      <RepositoryAndIssuePicker
        selectedIssueIds={duplicateIssue ? [duplicateIssue.id] : []}
        hiddenIssueIds={[data.id]}
        onPickerTypeChange={onPickerTypeChange}
        onIssueSelection={issues => duplicateIssueSelected(issues.length > 0 && issues[0] ? issues[0] : null)}
        defaultRepositoryNameWithOwner={data.repository.nameWithOwner}
        organization={data.repository.owner.login}
        pickerType={pickerType}
        anchorElement={props => {
          const {ref} = props as React.HTMLAttributes<HTMLButtonElement> & {
            ref: React.MutableRefObject<HTMLButtonElement | null>
          }
          if (ref) {
            ref.current = anchorRef.current
          }
          // We don't actually want to render any element, as we are relying on the rendered section header above
          return <></>
        }}
      />
    </>
  )
}

type UpdateStatusButtonProps = {
  issueState: IssueState
  buttonState: CloseButtonState
  disabled?: boolean
  onClose?: (reason: IssueClosedStateReason) => void
  onReopen?: () => void
  onAction?: () => void
  hasComment: boolean
  size?: 'small' | 'medium'
  viewerCanReopen?: boolean
  viewerCanClose?: boolean
  duplicateIssue?: IssuePickerItem
}

const UpdateStateButton: React.FC<UpdateStatusButtonProps> = ({
  disabled = false,
  issueState,
  buttonState,
  onClose,
  onReopen,
  onAction,
  hasComment = false,
  size = 'medium',
  viewerCanReopen,
  viewerCanClose,
  duplicateIssue,
}: UpdateStatusButtonProps) => {
  if (issueState !== 'OPEN' && issueState !== 'CLOSED') {
    // This shouldn't happen.  Should this throw?
    return null
  }

  const reason = getReason(issueState, buttonState)
  const viewerCanPerformAction = getViewerCanPerformAction(issueState, buttonState, viewerCanReopen, viewerCanClose)
  const onStateChange = getOnStateChange(issueState, buttonState, reason, onClose, onReopen)

  return createUpdateStatusButton(
    disabled,
    hasComment,
    issueState,
    reason,
    onAction,
    onStateChange,
    viewerCanPerformAction,
    size,
    duplicateIssue,
  )
}

type UpdateStateButtonOptionsProps = {
  buttonState: CloseButtonState
  setButtonState: (state: CloseButtonState) => void
  issueState: IssueState
  issueStateReason: IssueStateReason | null | undefined
  canClose: boolean
  canReopen: boolean
  viewerCanClose?: boolean
  viewerCanReopen?: boolean
  duplicateIssueSelected: (issue: IssuePickerItem | null) => void
  setIsDuplicateDialogOpen: (isOpen: boolean) => void
}

const UpdateStateButtonOptions: React.FC<UpdateStateButtonOptionsProps> = ({
  buttonState,
  setButtonState,
  issueState,
  issueStateReason,
  canClose,
  canReopen,
  viewerCanClose,
  viewerCanReopen,
  setIsDuplicateDialogOpen,
}: UpdateStateButtonOptionsProps) => {
  const onCloseAsDuplicateSelected = useCallback(() => {
    setButtonState('DUPLICATE')
    setIsDuplicateDialogOpen(true)
  }, [setButtonState, setIsDuplicateDialogOpen])

  return (
    <ActionList
      showDividers
      selectionVariant="single"
      aria-roledescription={LABELS.updateIssueRoleDescription}
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 1, // gap is needed to add some space between items as a workaround to force the menu to open upwards
      }}
    >
      {issueState === 'CLOSED' && (viewerCanReopen || viewerCanReopen === undefined) && (
        <ActionList.Item
          key={'reopen-issue-option'}
          onSelect={() => setButtonState('OPEN')}
          selected={buttonState === 'OPEN'}
          disabled={!canReopen || !viewerCanReopen}
        >
          <ActionList.LeadingVisual sx={{color: 'open.fg'}}>
            <IssueReopenedIcon />
          </ActionList.LeadingVisual>
          {LABELS.reOpenIssue}
        </ActionList.Item>
      )}
      {(issueState === 'OPEN' || issueStateReason === 'NOT_PLANNED') &&
        (viewerCanClose || viewerCanClose === undefined) && (
          <ActionList.Item
            key={'close-issue-option'}
            onSelect={() => setButtonState('CLOSED')}
            selected={buttonState === 'CLOSED'}
            disabled={!canClose || !viewerCanClose}
          >
            <ActionList.LeadingVisual sx={{color: 'done.fg'}}>
              <IssueClosedIcon />
            </ActionList.LeadingVisual>
            {LABELS.closeAsCompleted}
            <ActionList.Description variant="block">{LABELS.actionListCompletedDescription}</ActionList.Description>
          </ActionList.Item>
        )}
      {(issueState === 'OPEN' || (issueState === 'CLOSED' && issueStateReason !== 'NOT_PLANNED')) && viewerCanClose && (
        <ActionList.Item
          key={'skip-issue-option'}
          onSelect={() => setButtonState('NOT_PLANNED')}
          selected={buttonState === 'NOT_PLANNED'}
          disabled={!canClose}
        >
          <ActionList.LeadingVisual>
            <SkipIcon />
          </ActionList.LeadingVisual>
          {LABELS.closeAsNotPlanned}
          <ActionList.Description variant="block">{LABELS.actionListNotPlannedNewDescription}</ActionList.Description>
        </ActionList.Item>
      )}
      {(issueState === 'OPEN' || (issueState === 'CLOSED' && issueStateReason !== 'DUPLICATE')) && viewerCanClose && (
        <ActionList.Item
          key={'close-duplicate-issue-option'}
          onSelect={onCloseAsDuplicateSelected}
          selected={buttonState === 'DUPLICATE'}
          disabled={!canClose}
        >
          <ActionList.LeadingVisual>
            <SkipIcon />
          </ActionList.LeadingVisual>
          <ActionList.TrailingVisual>
            <ArrowRightIcon />
          </ActionList.TrailingVisual>
          {LABELS.closeAsDuplicate}
          <ActionList.Description variant="block">{LABELS.actionListDuplicateDescription}</ActionList.Description>
        </ActionList.Item>
      )}
    </ActionList>
  )
}

const getInitialButtonState = (state: IssueState) => {
  return state === 'CLOSED' ? 'OPEN' : 'CLOSED'
}

function createUpdateStatusButton(
  disabled = false,
  hasComment: boolean,
  issueState: IssueState,
  reason?: IssueClosedStateReason,
  onAction?: () => void,
  onStateChange?: () => void,
  viewerCanPerformAction?: boolean,
  size?: 'small' | 'medium',
  duplicateIssue?: IssuePickerItem,
) {
  const color = getColorForReason(reason)
  const icon = getIconForReason(reason)
  const label = getLabelForReason(issueState, hasComment, reason, duplicateIssue)
  const tooltipText = getTooltipTextForReason(reason)
  const tooltipId = getTooltipIdForReason(reason)

  const button = (
    <Button
      onClick={() => {
        onAction?.()
        onStateChange?.()
      }}
      leadingVisual={() => <Octicon icon={icon} sx={{color}} />}
      disabled={disabled || !onStateChange || !viewerCanPerformAction}
      size={size}
    >
      {label}
    </Button>
  )

  return viewerCanPerformAction ? (
    button
  ) : (
    <Tooltip text={tooltipText} direction="w" data-testid={tooltipId}>
      {button}
    </Tooltip>
  )
}

function getTooltipIdForReason(reason?: IssueClosedStateReason) {
  if (reason) {
    return 'close-button-tooltip'
  }
  return 'reopen-button-tooltip'
}

function getTooltipTextForReason(reason?: IssueClosedStateReason) {
  if (reason) {
    return ERRORS.missingClosePermission
  }
  return ERRORS.missingReopenPermission
}

function getColorForReason(reason?: IssueClosedStateReason) {
  switch (reason) {
    case 'COMPLETED':
      return 'done.fg'
    case 'NOT_PLANNED':
      return 'fg.muted'
    case 'DUPLICATE':
      return 'fg.muted'
    case undefined:
      return 'open.fg'
    default:
      return 'fg.default'
  }
}

function getIconForReason(reason?: IssueClosedStateReason) {
  switch (reason) {
    case 'COMPLETED':
      return IssueClosedIcon
    case 'NOT_PLANNED':
      return SkipIcon
    case 'DUPLICATE':
      return SkipIcon
    case undefined:
      return IssueReopenedIcon
    default:
      return IssueClosedIcon
  }
}

function getLabelForReason(
  issueState: IssueState,
  hasComment: boolean,
  reason?: IssueClosedStateReason,
  duplicateIssue?: IssuePickerItem,
) {
  if (issueState === 'OPEN') {
    if (reason === 'DUPLICATE') {
      return duplicateIssue ? LABELS.closeAsDuplicateOf(duplicateIssue.number) : LABELS.closeAsDuplicate
    }

    return hasComment ? LABELS.closeIssueWithComment : LABELS.closeIssue
  }
  if (reason === 'NOT_PLANNED') {
    return LABELS.closeAsNotPlanned
  }
  if (reason === 'DUPLICATE') {
    return duplicateIssue ? LABELS.closeAsDuplicateOf(duplicateIssue.number) : LABELS.closeAsDuplicate
  }
  if (reason === undefined) {
    return LABELS.reOpenIssue
  }
  return LABELS.closeAsCompleted
}

function getReason(issueState: IssueState, buttonState: CloseButtonState) {
  if (buttonState === 'NOT_PLANNED') {
    return 'NOT_PLANNED'
  }
  if (buttonState === 'DUPLICATE') {
    return 'DUPLICATE'
  }
  if (issueState === 'OPEN') {
    return 'COMPLETED'
  }
  if (buttonState === 'CLOSED') {
    return 'COMPLETED'
  }

  return undefined
}

function getViewerCanPerformAction(
  issueState: IssueState,
  buttonState: CloseButtonState,
  viewerCanReopen: boolean | undefined,
  viewerCanClose: boolean | undefined,
) {
  return issueState === 'CLOSED' && buttonState === 'OPEN' ? viewerCanReopen : viewerCanClose
}

function getOnStateChange(
  issueState: IssueState,
  buttonState: CloseButtonState,
  reason?: IssueClosedStateReason,
  onClose?: (reason: IssueClosedStateReason) => void,
  onReopen?: () => void,
) {
  return issueState === 'CLOSED' && buttonState === 'OPEN' ? () => onReopen?.() : () => reason && onClose?.(reason)
}
