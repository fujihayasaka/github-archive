import {DataTable} from '@primer/react/experimental'
import type {ImageDefinition} from '../types/types'
import {splitCuratedImageDefinitions} from '../helpers/utils'
import {CheckCircleIcon, KebabHorizontalIcon, XCircleIcon} from '@primer/octicons-react'

import {ActionList, ActionMenu, IconButton, Link, VisuallyHidden} from '@primer/react'
import {CuratedImagesTableConstants} from '../helpers/constants'
import {useState} from 'react'
import {NewEditCuratedImageDialog} from './NewEditCuratedImageDialog'
import {useNavigate} from '@github-ui/use-navigate'
import {DeleteCuratedImageDialog} from './DeleteCuratedImageDialog'
import {Urls, curatedImagePath} from '../helpers/paths'

interface CuratedImagesTableProps {
  imageDefinitions: ImageDefinition[]
}

export function CuratedImagesTable(props: CuratedImagesTableProps) {
  const [showEditImageDialog, setShowEditImageDialog] = useState<number | null>(null)
  const [showDeleteImageDialog, setShowDeleteImageDialog] = useState<number | null>(null)
  const navigate = useNavigate()

  const {imageDefinitionsList, imagePointersList} = splitCuratedImageDefinitions(props.imageDefinitions)

  const deleteActionButton = (imageDef: ImageDefinition): JSX.Element => {
    if (imagePointersList.some(d => d.pointsToImageDefinitionId === imageDef.id)) {
      return (
        <ActionList.Item
          variant="danger"
          disabled
          inactiveText={CuratedImagesTableConstants.failedDeleteReferencedByPointer}
        >
          {CuratedImagesTableConstants.deleteAction}
        </ActionList.Item>
      )
    }

    if (imageDef.imageVersionsCount > 0) {
      return (
        <ActionList.Item
          variant="danger"
          disabled
          inactiveText={CuratedImagesTableConstants.failedDeleteHasImageVersions}
        >
          {CuratedImagesTableConstants.deleteAction}
        </ActionList.Item>
      )
    }

    return (
      <ActionList.Item
        variant="danger"
        onSelect={() => setShowDeleteImageDialog(imageDef.id)}
        onClick={() => setShowDeleteImageDialog(imageDef.id)}
      >
        {CuratedImagesTableConstants.deleteAction}
      </ActionList.Item>
    )
  }

  return (
    <DataTable
      aria-labelledby="curated-images"
      aria-describedby="curated-images-subtitle"
      data={imageDefinitionsList}
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
              <CheckCircleIcon fill="var(--fgColor-success)" size={16} />
            ) : (
              <XCircleIcon fill="var(--fgColor-danger)" size={16} />
            )
          },
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
                    <ActionList.Item
                      disabled={row.imageVersionsCount === 0}
                      onSelect={() => navigate(curatedImagePath(row.id))}
                    >
                      {CuratedImagesTableConstants.viewImageVersions}
                    </ActionList.Item>
                    <ActionList.Divider />
                    <ActionList.Item
                      onClick={() => setShowEditImageDialog(row.id)}
                      onSelect={() => setShowEditImageDialog(row.id)}
                    >
                      {CuratedImagesTableConstants.editAction}
                    </ActionList.Item>
                    {showEditImageDialog === row.id && (
                      <NewEditCuratedImageDialog closeDialog={() => setShowEditImageDialog(0)} imageDefinition={row} />
                    )}
                    {deleteActionButton(row)}
                    {showDeleteImageDialog === row.id && (
                      <DeleteCuratedImageDialog
                        closeDialog={() => setShowDeleteImageDialog(null)}
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
