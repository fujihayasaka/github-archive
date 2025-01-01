import {DataTable} from '@primer/react/experimental'
import type {ImageDefinition} from '../types/types'
import {CheckCircleIcon, KebabHorizontalIcon, XCircleIcon} from '@primer/octicons-react'

import {ActionList, ActionMenu, IconButton, Link, VisuallyHidden} from '@primer/react'
import {CuratedImagePointersTableConstants} from '../helpers/constants'
import {useState} from 'react'
import {NewEditCuratedImagePointerDialog} from './NewEditCuratedImagePointerDialog'
import {DeleteCuratedImageDialog} from './DeleteCuratedImageDialog'
import {splitCuratedImageDefinitions} from '../helpers/utils'
import {Urls} from '../helpers/paths'

interface CuratedImagesPointerTableProps {
  imageDefinitions: ImageDefinition[]
}

export function CuratedImagesPointerTable(props: CuratedImagesPointerTableProps) {
  const {imagePointersList} = splitCuratedImageDefinitions(props.imageDefinitions)

  const [showEditImagePointerDialog, setShowEditImagePointerDialog] = useState<number | null>(null)
  const [showDeleteImagePointerDialog, setShowDeleteImagePointerDialog] = useState<number | null>(null)

  return (
    <DataTable
      aria-labelledby="pointers"
      aria-describedby="pointers-subtitle"
      data={imagePointersList}
      columns={[
        {
          header: 'ID',
          field: 'id',
          rowHeader: true,
        },
        {
          header: 'Name',
          field: 'name',
        },
        {
          header: 'Architecture',
          field: 'architecture',
        },
        {
          header: 'OsType',
          field: 'osType',
        },
        {
          header: 'Enabled',
          field: 'enabled',
          renderCell: row => {
            return row.featureFlag !== '' ? (
              <Link href={Urls.featureFlagUrl(row.featureFlag)}>Feature Flag</Link>
            ) : row.enabled ? (
              <CheckCircleIcon size={16} />
            ) : (
              <XCircleIcon size={16} />
            )
          },
        },
        {
          header: 'Points To',
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
                    <ActionList.Item
                      onClick={() => setShowEditImagePointerDialog(row.id)}
                      onSelect={() => setShowEditImagePointerDialog(row.id)}
                    >
                      {CuratedImagePointersTableConstants.editAction}
                    </ActionList.Item>
                    {showEditImagePointerDialog === row.id && (
                      <NewEditCuratedImagePointerDialog
                        closeDialog={() => setShowEditImagePointerDialog(null)}
                        imagePointer={row}
                        imageDefinitions={props.imageDefinitions}
                      />
                    )}
                    <ActionList.Item
                      variant="danger"
                      onClick={() => setShowDeleteImagePointerDialog(row.id)}
                      onSelect={() => setShowDeleteImagePointerDialog(row.id)}
                    >
                      {CuratedImagePointersTableConstants.deleteAction}
                    </ActionList.Item>
                    {showDeleteImagePointerDialog === row.id && (
                      <DeleteCuratedImageDialog
                        closeDialog={() => setShowDeleteImagePointerDialog(null)}
                        imageDefinition={row}
                      />
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
