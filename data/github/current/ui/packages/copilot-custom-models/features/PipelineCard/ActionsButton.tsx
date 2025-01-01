import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {useCancelDialog} from '../../components/CancelDialogProvider'
import {usePipelineDetails} from '../PipelineDetails'
import {useNavigateWithFlashBanner} from '../NavigateWithFlashBanner'
import {useDeleteModel} from '../../components/DeleteDialogProvider'
import {formatDistanceToNow} from 'date-fns'

export function ActionsButton() {
  const {
    canViewDetails,
    cardPipeline: {canCancel, cancelPath, canDelete, canRetrain, editPath, showPath, showRetrain},
    rateLimitResetAt,
  } = usePipelineDetails()
  const {navigate} = useNavigateWithFlashBanner()
  const {openDialogForCancelPath} = useCancelDialog()
  const {openDialog: openDeleteModelDialog} = useDeleteModel()

  const anyActions = [canViewDetails, showRetrain, canCancel, canDelete].some(Boolean)

  if (!anyActions) return null

  const handleViewDetailsClick = () => navigate(showPath)
  const handleRetrainClick = () => navigate(editPath)
  const handleCancelClick = () => openDialogForCancelPath(cancelPath)
  const handleDeleteClick = () => openDeleteModelDialog()

  const duration = rateLimitResetAt ? formatDistanceToNow(Date.parse(rateLimitResetAt)) : ''
  const retrainInactiveText = duration
    ? `Unavailable due to training rate limit. Retrain available in ${duration}.`
    : 'Unavailable due to training rate limit. Check back later.'

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton aria-label="More pipeline actions" icon={KebabHorizontalIcon} variant="invisible" />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList>
          {canViewDetails && <ActionList.Item onSelect={handleViewDetailsClick}>Training details</ActionList.Item>}

          {showRetrain && (
            <ActionList.Item inactiveText={canRetrain ? undefined : retrainInactiveText} onSelect={handleRetrainClick}>
              Retrain model
            </ActionList.Item>
          )}

          {canCancel && (
            <ActionList.Item onSelect={handleCancelClick} variant="danger">
              Cancel training
            </ActionList.Item>
          )}

          {canDelete && (
            <ActionList.Item onSelect={handleDeleteClick} variant="danger">
              Delete model
            </ActionList.Item>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
