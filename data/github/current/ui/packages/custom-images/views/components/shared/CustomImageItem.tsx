import {useRef, useState} from 'react'
import {IconButton, Box} from '@primer/react'
import {TrashIcon} from '@primer/octicons-react'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import {ListItem} from '@github-ui/list-view/ListItem'
import {PlatformIcon} from '@github-ui/github-hosted-runners-settings/views/components/shared/PlatformIcon'
import type {PlatformOsType} from '@github-ui/github-hosted-runners-settings/types/platform'
import {ImageDefinitionState} from '@github-ui/github-hosted-runners-settings/types/image'
import {imageVersionsListPath} from '../../../helpers/paths'
import {DeleteCustomImageDialog} from './DeleteCustomImageDialog'
import {ImageStateIndicator} from './ImageStateIndicator'

import styles from './CustomImageItem.module.css'

interface Props {
  imageDefinitionId: string | number
  entityLogin: string
  isEnterprise: boolean
  osType: PlatformOsType
  displayName: string
  versionsCount: number | undefined
  totalVersionsSize: number | undefined
  latestVersion: string | undefined
  state: ImageDefinitionState | null
  canWriteCustomImages: boolean
}

export default function CustomImageItem({
  imageDefinitionId,
  entityLogin,
  isEnterprise,
  osType,
  displayName,
  versionsCount = 0,
  totalVersionsSize = 0,
  latestVersion,
  state,
  canWriteCustomImages,
}: Props) {
  const [deleteDialogIsOpen, setDeleteDialogIsOpen] = useState(false)
  const [imageDefinitionState, setImageDefinitionState] = useState<ImageDefinitionState | null>(state)
  const contextMenuButtonRef = useRef<HTMLButtonElement>(null)

  function openDeleteDialog() {
    setDeleteDialogIsOpen(true)
  }

  function closeDeleteDialog() {
    setDeleteDialogIsOpen(false)
    contextMenuButtonRef.current?.focus()
  }

  function handleDeleteDialogSuccess() {
    setImageDefinitionState(ImageDefinitionState.Deleting)
    setDeleteDialogIsOpen(false)
  }

  function handleTrashClick() {
    openDeleteDialog()
  }

  return (
    <>
      <ListItem
        title={
          <ListItemTitle
            value={displayName}
            href={imageVersionsListPath({imageDefinitionId: imageDefinitionId.toString(), isEnterprise, entityLogin})}
            trailingBadges={latestVersion ? [<ListItemTrailingBadge title={`v${latestVersion}`} key={0} />] : []}
          />
        }
        metadata={
          <ListItemMetadata>
            {!!imageDefinitionState && imageDefinitionState !== ImageDefinitionState.Ready && (
              <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'center'}}>
                <ImageStateIndicator imageState={imageDefinitionState} />
              </Box>
            )}
            {imageDefinitionState !== ImageDefinitionState.Deleting && canWriteCustomImages && (
              // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
              <IconButton
                unsafeDisableTooltip
                icon={TrashIcon}
                aria-label="Delete"
                variant="invisible"
                onClick={handleTrashClick}
                data-testid="trash-button"
                sx={{ml: 2}}
              />
            )}
          </ListItemMetadata>
        }
        data-testid="custom-image-item"
      >
        <ListItemLeadingContent className={styles.ListItemLeadingContent_0}>
          <PlatformIcon className="color-fg-muted" size={16} osType={osType} />
        </ListItemLeadingContent>
        <ListItemMainContent>
          <ListItemDescription>
            <ImageDescription totalVersionsSize={totalVersionsSize} versionsCount={versionsCount} />
          </ListItemDescription>
        </ListItemMainContent>
      </ListItem>
      {deleteDialogIsOpen && (
        <DeleteCustomImageDialog
          imageDefinitionId={imageDefinitionId}
          entityLogin={entityLogin}
          isEnterprise={isEnterprise}
          onCancel={closeDeleteDialog}
          onDismiss={closeDeleteDialog}
          onSuccess={handleDeleteDialogSuccess}
        />
      )}
    </>
  )
}

function ImageDescription({totalVersionsSize, versionsCount}: {totalVersionsSize: number; versionsCount: number}) {
  const versionString = versionsCount === 1 ? 'version' : 'versions'

  return (
    <span className="text-small color-fg-muted flex-shrink-0" data-testid="image-description">
      {versionsCount} {versionString} with {totalVersionsSize} GB total
    </span>
  )
}
