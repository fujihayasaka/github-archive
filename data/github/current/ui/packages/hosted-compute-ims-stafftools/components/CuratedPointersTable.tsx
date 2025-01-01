import {DataTable} from '@primer/react/experimental'
import type {ImageDefinition} from '../types/types'
import {KebabHorizontalIcon} from '@primer/octicons-react'

import {ActionList, ActionMenu, IconButton, VisuallyHidden} from '@primer/react'
import {useState} from 'react'
import {NewEditCuratedImagePointerDialog} from './NewEditCuratedImagePointerDialog'
import {DeleteCuratedImageDialog} from './DeleteCuratedImageDialog'
import {ImageDefinitionEnabledState} from './ImageDefinitionEnabledState'
import {useNavigate} from '@github-ui/use-navigate'
import {curatedImageDetailsUrl} from '../helpers/urls'

interface CuratedPointersTableProps {
  pointerImages: ImageDefinition[]
  curatedImages: ImageDefinition[]
}

export function CuratedPointersTable(props: CuratedPointersTableProps) {
  const [showEditImagePointerDialog, setShowEditImagePointerDialog] = useState<number | null>(null)
  const [showDeleteImagePointerDialog, setShowDeleteImagePointerDialog] = useState<number | null>(null)
  const navigate = useNavigate()

  return (
    <DataTable
      aria-labelledby="pointers"
      aria-describedby="pointers-subtitle"
      data={props.pointerImages}
      cellPadding="condensed"
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
          header: 'Points To ID',
          field: 'pointsToImageDefinitionId',
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
                      onClick={() => setShowEditImagePointerDialog(row.id)}
                      onSelect={() => setShowEditImagePointerDialog(row.id)}
                    >
                      Edit pointer
                    </ActionList.Item>
                    {showEditImagePointerDialog === row.id && (
                      <NewEditCuratedImagePointerDialog
                        closeDialog={() => setShowEditImagePointerDialog(null)}
                        pointerImage={row}
                        referencedImagesCandidates={props.curatedImages}
                        pointerOwner={row.ownerId}
                      />
                    )}
                    <ActionList.Item
                      variant="danger"
                      onClick={() => setShowDeleteImagePointerDialog(row.id)}
                      onSelect={() => setShowDeleteImagePointerDialog(row.id)}
                    >
                      Delete pointer
                    </ActionList.Item>
                    {showDeleteImagePointerDialog === row.id && (
                      <DeleteCuratedImageDialog
                        closeDialog={() => setShowDeleteImagePointerDialog(null)}
                        curatedImage={row}
                      />
                    )}
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            )
          },
        },
      ]}
      initialSortColumn="id"
      initialSortDirection="ASC"
    />
  )
}
