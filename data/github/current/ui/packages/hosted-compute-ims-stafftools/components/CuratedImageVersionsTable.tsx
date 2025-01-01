import type {ImageDefinition, ImageVersion} from '../types/types'
import {ActionList, ActionMenu, IconButton, VisuallyHidden} from '@primer/react'
import {CheckCircleIcon, XCircleIcon, KebabHorizontalIcon, LinkExternalIcon} from '@primer/octicons-react'
import {DataTable, Table} from '@primer/react/experimental'

import {useState, useEffect} from 'react'
import {CuratedImageVersionStateDetailsDialog} from './CuratedImageVersionStateDetailsDialog'
import {DeleteCuratedImageVersionDialog} from './DeleteCuratedImageVersionDialog'
import {updateCuratedImageVersion} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {curatedImagePath} from '../helpers/paths'
import {CuratedImageVersionDialogConstants} from '../helpers/constants'

interface CuratedImageVersionsTableProps {
  imageVersions: ImageVersion[]
  imageDefinition: ImageDefinition
}

export function CuratedImageVersionsTable(props: CuratedImageVersionsTableProps) {
  const [showStateDetailsDialog, setShowStateDetailsDialog] = useState<number | null>(null)
  const [showDeleteDialog, setShowDeleteDialog] = useState<number | null>(null)
  const flashBanner = useFlashBannerState()

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  const handleEnableDisable = async (imageVersion: ImageVersion) => {
    const response = await updateCuratedImageVersion({
      id: imageVersion.imageDefinitionId,
      version: imageVersion.version,
      enabled: !imageVersion.enabled,
    })
    if (response.ok) {
      flashBanner.showInfo(CuratedImageVersionDialogConstants.Update.successBanner)
      window.location.assign(curatedImagePath(props.imageDefinition.id))
    } else {
      flashBanner.showError(response.error)
    }
  }

  const deleteImageVersionActionButton = (imageVersion: ImageVersion): JSX.Element => {
    if (imageVersion.state === 'Deleting') {
      return (
        <ActionList.Item variant="danger" disabled>
          Delete
        </ActionList.Item>
      )
    }

    return (
      <ActionList.Item
        variant="danger"
        onSelect={() => setShowDeleteDialog(imageVersion.id)}
        onClick={() => setShowDeleteDialog(imageVersion.id)}
      >
        Delete
      </ActionList.Item>
    )
  }

  return (
    <div>
      <FlashBanner state={flashBanner.state} />
      <Table.Container>
        <DataTable
          data={props.imageVersions}
          columns={[
            {
              header: 'ID',
              field: 'id',
              rowHeader: true,
            },
            {
              header: 'Version',
              field: 'version',
            },
            {
              header: 'State',
              field: 'state',
            },
            {
              header: 'State Details',
              field: 'stateDetails',
              renderCell: row => {
                return (
                  <>
                    {row.stateDetails !== '' && (
                      <IconButton
                        icon={LinkExternalIcon}
                        aria-label="State details"
                        onClick={() => setShowStateDetailsDialog(row.id)}
                        variant="invisible"
                      />
                    )}
                    {showStateDetailsDialog === row.id && (
                      <CuratedImageVersionStateDetailsDialog
                        imageVersion={row}
                        closeDialog={() => setShowStateDetailsDialog(null)}
                      />
                    )}
                  </>
                )
              },
            },
            {
              header: 'Size GB',
              field: 'sizeGb',
            },
            {
              header: 'Enabled',
              field: 'enabled',
              renderCell: row => {
                return row.enabled ? <CheckCircleIcon size={16} /> : <XCircleIcon size={16} />
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
                        aria-label={`Actions: ${row.version}`}
                        title={`Actions: ${row.version}`}
                        icon={KebabHorizontalIcon}
                        variant="invisible"
                        unsafeDisableTooltip
                      />
                    </ActionMenu.Anchor>
                    <ActionMenu.Overlay>
                      <ActionList>
                        <ActionList.Item onSelect={() => handleEnableDisable(row)}>
                          {row.enabled ? 'Disable' : 'Enable'}
                        </ActionList.Item>
                        {deleteImageVersionActionButton(row)}
                        {showDeleteDialog === row.id && (
                          <DeleteCuratedImageVersionDialog
                            closeDialog={() => setShowDeleteDialog(null)}
                            imageVersion={row}
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
      </Table.Container>
    </div>
  )
}
