// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {DuplicateIcon, KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useConfirm} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'

import {ASSIGNED_TO_ME_VIEW} from '../../../constants/view-constants'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {useAppNavigate} from '../../../hooks/use-app-navigate'
import type {ViewOptionsButtonCurrentViewFragment$key} from './__generated__/ViewOptionsButtonCurrentViewFragment.graphql'
import {LABELS} from '../../../constants/labels'
import {VALUES} from '../../../constants/values'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import {commitRemoveUserViewMutation} from '../../../mutations/remove-user-view-mutation'
import styles from './ViewOptionsButton.module.css'
import {useTrackingRef} from '@github-ui/use-tracking-ref'

type ViewOptionsButtonProps = {
  currentView: ViewOptionsButtonCurrentViewFragment$key
}

export const ViewOptionsButton = ({currentView}: ViewOptionsButtonProps) => {
  const {
    id: viewId,
    name: viewName,
    query: viewQuery,
    description: viewDescription,
    color: viewColor,
    icon: viewIcon,
  } = useFragment<ViewOptionsButtonCurrentViewFragment$key>(
    graphql`
      fragment ViewOptionsButtonCurrentViewFragment on Shortcutable {
        id
        name
        description
        icon
        color
        query
      }
    `,
    currentView,
  )
  const {isCustomView, setIsEditing, canEditView, savedViewsCount} = useQueryContext()
  const {commitUserViewDuplicate} = useQueryEditContext()
  const relayEnvironment = useRelayEnvironment()
  const maxViewsReached = savedViewsCount >= VALUES.viewsPageSize
  const viewOptionsButtonRef = useRef<HTMLButtonElement>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const prevIsDeletingRef = useTrackingRef(isDeleting)

  const {addToast} = useToastContext()
  const {navigateToSavedView, navigateToView} = useAppNavigate()
  const confirm = useConfirm()

  const editView = useCallback(() => {
    setIsEditing(true)
  }, [setIsEditing])

  const duplicateView = useCallback(() => {
    const args = {
      viewName,
      viewIcon,
      viewColor,
      viewDescription,
      viewQuery,
      onError: () =>
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: LABELS.views.duplicateError,
        }),
      relayEnvironment,
    }
    commitUserViewDuplicate({
      ...args,
      onSuccess: ({createDashboardSearchShortcut}) => {
        if (createDashboardSearchShortcut?.shortcut) {
          navigateToSavedView(createDashboardSearchShortcut.shortcut.id, {isEditing: false})
        }
      },
    })
  }, [
    viewName,
    viewIcon,
    viewColor,
    viewDescription,
    viewQuery,
    relayEnvironment,
    addToast,
    commitUserViewDuplicate,
    navigateToSavedView,
  ])

  useEffect(() => {
    if (prevIsDeletingRef.current && !isDeleting) {
      viewOptionsButtonRef.current?.focus()
    }
  }, [isDeleting, prevIsDeletingRef])

  const deleteView = useCallback(async () => {
    if (!viewId) return

    setIsDeleting(true)

    const performDelete = await confirm({
      title: LABELS.views.deleteTitle,
      content: LABELS.views.deleteContent(viewName),
      confirmButtonContent: LABELS.views.deleteConfirmationButton,
      confirmButtonType: 'danger',
    })

    if (!performDelete) {
      setIsDeleting(false)
      return
    }

    const payload = {
      environment: relayEnvironment,
      input: {shortcutId: viewId},
      onError: () =>
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: LABELS.views.deleteError,
        }),
      onCompleted: () => {
        navigateToView({viewId: ASSIGNED_TO_ME_VIEW.id, canEditView: true})
      },
    }

    commitRemoveUserViewMutation(payload)

    setIsDeleting(false)
  }, [addToast, confirm, navigateToView, relayEnvironment, viewId, viewName])

  const canDuplicateView = viewId !== VIEW_IDS.repository && (canEditView || !isCustomView)

  const canModifyCustomView = isCustomView(viewId) && canEditView

  if (!canModifyCustomView && !canDuplicateView) return null

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          icon={KebabHorizontalIcon}
          aria-label={LABELS.views.editButtonAriaLabel}
          variant="invisible"
          ref={viewOptionsButtonRef}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="small">
        <ActionList>
          {canModifyCustomView && (
            <ActionList.Item onSelect={editView}>
              <ActionList.LeadingVisual>
                <PencilIcon />
              </ActionList.LeadingVisual>
              {LABELS.views.edit}
            </ActionList.Item>
          )}
          {canDuplicateView && (
            <ActionList.Item onSelect={duplicateView} disabled={maxViewsReached}>
              <ActionList.LeadingVisual>
                <DuplicateIcon />
              </ActionList.LeadingVisual>
              {LABELS.views.duplicate}
              {maxViewsReached && (
                <ActionList.Description variant="block">
                  <span className={styles.warning}>{LABELS.views.maxViewsReached}</span>
                </ActionList.Description>
              )}
            </ActionList.Item>
          )}
          {canModifyCustomView && (
            <>
              <ActionList.Divider />
              <ActionList.Item variant="danger" onSelect={deleteView}>
                <ActionList.LeadingVisual>
                  <TrashIcon />
                </ActionList.LeadingVisual>
                {LABELS.views.delete}
              </ActionList.Item>
            </>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
