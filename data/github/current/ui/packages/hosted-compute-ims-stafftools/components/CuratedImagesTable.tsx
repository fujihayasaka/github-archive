import {DataTable} from '@primer/react/experimental'
import type {ImageDefinition} from '../types/types'
import {KebabHorizontalIcon} from '@primer/octicons-react'

import {ActionList, ActionMenu, IconButton, VisuallyHidden} from '@primer/react'
import {useState} from 'react'
import {NewEditCuratedImageDialog} from './NewEditCuratedImageDialog'
import {useNavigate} from '@github-ui/use-navigate'
import {DeleteCuratedImageDialog} from './DeleteCuratedImageDialog'
import {curatedImageDetailsUrl} from '../helpers/urls'
import {ImageDefinitionEnabledState} from './ImageDefinitionEnabledState'

interface CuratedImagesTableProps {
  curatedImages: ImageDefinition[]
  pointerImages: ImageDefinition[]
}

export function CuratedImagesTable(props: CuratedImagesTableProps) {
  const [showEditImageDialog, setShowEditImageDialog] = useState<number | null>(null)
  const [showDeleteImageDialog, setShowDeleteImageDialog] = useState<number | null>(null)
  const navigate = useNavigate()

  const deleteActionButton = (imageDef: ImageDefinition): JSX.Element => {
    if (props.pointerImages.some(d => d.pointsToImageDefinitionId === imageDef.id)) {
      return (
        <ActionList.Item variant="danger" disabled inactiveText="Image is referenced by pointer">
          Delete image
        </ActionList.Item>
      )
    }

    if (imageDef.imageVersionsCount > 0) {
      return (
        <ActionList.Item variant="danger" disabled inactiveText="Image has image versions">
          Delete image
        </ActionList.Item>
      )
    }

    return (
      <ActionList.Item
        variant="danger"
        onSelect={() => setShowDeleteImageDialog(imageDef.id)}
        onClick={() => setShowDeleteImageDialog(imageDef.id)}
      >
        Delete image
      </ActionList.Item>
    )
  }

  return (
    <DataTable
      aria-labelledby="curated-images"
      aria-describedby="curated-images-subtitle"
      data={props.curatedImages}
      cellPadding="condensed"
      initialSortColumn="id"
      initialSortDirection="ASC"
      columns={[
        {
          header: 'ID',
          field: 'id',
          rowHeader: true,
          sortBy: 'basic',
        },
        {
          header: 'Name',
          field: 'name',
          sortBy: 'alphanumeric',
        },
        {
          header: 'Platform',
          id: 'platform',
          renderCell: row => (
            <>
              {row.osType} ({row.architecture})
            </>
          ),
        },
        {
          header: 'Enabled',
          field: 'enabled',
          renderCell: row => <ImageDefinitionEnabledState imageDefinition={row} />,
        },
        {
          header: 'Versions',
          field: 'imageVersionsCount',
          renderCell: row => {
            return row.imageVersionsCount
          },
        },
        {
          id: 'actions',
          header: () => <VisuallyHidden>Actions</VisuallyHidden>,
          renderCell: row => {
            return (
              <ActionMenu>
                <ActionMenu.Anchor>
                  {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
                  <IconButton
                    aria-label={`Actions: ${row.name}`}
                    title={`Actions: ${row.name}`}
                    icon={KebabHorizontalIcon}
                    variant="invisible"
                    unsafeDisableTooltip
                  />
                </ActionMenu.Anchor>
                <ActionMenu.Overlay>
                  <ActionList>
                    <ActionList.Item onSelect={() => navigate(curatedImageDetailsUrl(row.id))}>Details</ActionList.Item>
                    <ActionList.Divider />
                    <ActionList.Item
                      onClick={() => setShowEditImageDialog(row.id)}
                      onSelect={() => setShowEditImageDialog(row.id)}
                    >
                      Edit image
                    </ActionList.Item>
                    {showEditImageDialog === row.id && (
                      <NewEditCuratedImageDialog
                        closeDialog={() => setShowEditImageDialog(null)}
                        curatedImage={row}
                        curatedOwner={row.ownerId}
                      />
                    )}
                    {deleteActionButton(row)}
                    {showDeleteImageDialog === row.id && (
                      <DeleteCuratedImageDialog closeDialog={() => setShowDeleteImageDialog(null)} curatedImage={row} />
                    )}
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            )
          },
        },
      ]}
    />
  )
}
