import {noop} from '@github-ui/noop'
import {PlusIcon} from '@primer/octicons-react'
import {Dialog, IconButton, useConfirm} from '@primer/react'
import {useCallback, useState} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {LABELS} from '../../constants/labels'
import {useQueryEditContext, useQueryContext} from '../../contexts/QueryContext'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {commitRemoveUserViewMutation} from '../../mutations/remove-user-view-mutation'
import {VALUES} from '../../constants/values'
import styles from './CreateSavedView.module.css'

type Props = {
  disabled: boolean
}

export function CreateSavedView({disabled}: Props) {
  const {commitUserViewCreate, dirtyDescription, dirtySearchQuery, dirtyTitle} = useQueryEditContext()
  const {dirtyViewId, setDirtyViewId, isNewView} = useQueryContext()
  const relayEnvironment = useRelayEnvironment()
  const confirm = useConfirm()
  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const {navigateToSavedView} = useAppNavigate()

  const openMaxViewsDialog = useCallback(() => {
    setIsDialogOpen(true)
  }, [setIsDialogOpen])

  const deleteDirtyView = useCallback(() => {
    if (dirtyViewId === undefined) {
      return
    }

    const payload = {
      environment: relayEnvironment,
      input: {shortcutId: dirtyViewId},
      onError: noop,
      onCompleted: noop,
    }

    commitRemoveUserViewMutation(payload)
  }, [dirtyViewId, relayEnvironment])

  const createNewView = useCallback(async () => {
    // When clicking the create view button while the user is editing a newly created view
    if (isNewView && (dirtyTitle !== LABELS.views.defaultName || dirtySearchQuery !== '' || dirtyDescription !== '')) {
      const discardChanges = await confirm({
        title: LABELS.views.unsavedChangesTitle,
        content: LABELS.views.unsavedChangesContent,
        confirmButtonType: 'danger',
      })

      if (!discardChanges) {
        return
      }

      deleteDirtyView()
    }

    commitUserViewCreate({
      onSuccess: ({createDashboardSearchShortcut}) => {
        if (createDashboardSearchShortcut?.shortcut) {
          setDirtyViewId(createDashboardSearchShortcut.shortcut.id)
          navigateToSavedView(createDashboardSearchShortcut.shortcut.id, {isNewView: true})
        }
      },
      relayEnvironment,
    })
  }, [
    commitUserViewCreate,
    confirm,
    deleteDirtyView,
    dirtyDescription,
    dirtySearchQuery,
    dirtyTitle,
    isNewView,
    navigateToSavedView,
    relayEnvironment,
    setDirtyViewId,
  ])

  return (
    <>
      <IconButton
        icon={PlusIcon}
        size="small"
        variant="invisible"
        aria-label={disabled ? LABELS.views.maxViewsTooltip : LABELS.views.createLink}
        onClick={disabled ? openMaxViewsDialog : createNewView}
        className={disabled ? styles.disabled : ''}
        inactive={disabled}
      />
      {disabled && isDialogOpen && (
        <Dialog
          title={`${LABELS.views.maxViewsTooltip} (${VALUES.viewsPageSize})`}
          onClose={() => setIsDialogOpen(false)}
        >
          {LABELS.views.maxViewsDescription}
        </Dialog>
      )}
    </>
  )
}
