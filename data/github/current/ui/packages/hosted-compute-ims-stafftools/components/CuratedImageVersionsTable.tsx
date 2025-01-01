import type {ImageDefinition, ImageVersion, ImageReference} from '../types/types'
import {ActionList, ActionMenu, IconButton, VisuallyHidden, Label, Text, Button} from '@primer/react'
import {CheckCircleIcon, XCircleIcon, KebabHorizontalIcon, LinkExternalIcon} from '@primer/octicons-react'
import {DataTable, Table} from '@primer/react/experimental'

import {useState, useEffect} from 'react'
import {CuratedImageVersionStateDetailsDialog} from './CuratedImageVersionStateDetailsDialog'
import {DeleteCuratedImageVersionDialog} from './DeleteCuratedImageVersionDialog'
import {updateCuratedImageVersion, getImageReference} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {curatedImagePath} from '../helpers/paths'
import {CuratedImageVersionDialogConstants} from '../helpers/constants'
import {ImageReferenceDialog} from './ImageReferenceDialog'

interface CuratedImageVersionsTableProps {
  imageVersions: ImageVersion[]
  imageDefinition: ImageDefinition
}

export function CuratedImageVersionsTable(props: CuratedImageVersionsTableProps) {
  const [showStateDetailsDialog, setShowStateDetailsDialog] = useState<number | null>(null)
  const [showDeleteDialog, setShowDeleteDialog] = useState<number | null>(null)
  const [showImageReferenceDialog, setShowImageReferenceDialog] = useState<number | 'latest' | null>(null)
  const flashBanner = useFlashBannerState()
  const [imageReference, setImageReference] = useState<ImageReference | null>(null)

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

  const handleShowImageReference = async (imageVersion: ImageVersion) => {
    const response = await getImageReference({
      id: props.imageDefinition.id,
      version: imageVersion.version,
    })
    if (response.ok) {
      const responseImageReference = (response.body as {imageReference: ImageReference}).imageReference
      setImageReference(responseImageReference)
      setShowImageReferenceDialog(imageVersion.id || 'latest')
    } else {
      flashBanner.showError(response.error)
    }
  }

  return (
    <div>
      <FlashBanner state={flashBanner.state} />
      {showImageReferenceDialog === 'latest' && imageReference ? (
        <ImageReferenceDialog imageReference={imageReference} closeDialog={() => setShowImageReferenceDialog(null)} />
      ) : null}
      <Table.Container>
        <Table.Actions>
          <Button onClick={() => handleShowImageReference({version: 'latest'} as ImageVersion)}>
            Latest Image Reference
          </Button>
        </Table.Actions>
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
              renderCell: row => {
                return (
                  <Text as="span" weight="normal">
                    {row.version} {row.isLatest && <Label>Latest</Label>}
                  </Text>
                )
              },
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
                return row.enabled ? (
                  <CheckCircleIcon fill="var(--fgColor-success)" size={16} />
                ) : (
                  <XCircleIcon fill="var(--fgColor-danger)" size={16} />
                )
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
                        <ActionList.Item
                          onSelect={() => handleShowImageReference(row)}
                          onClick={() => handleShowImageReference(row)}
                        >
                          Image Reference
                        </ActionList.Item>
                        {showImageReferenceDialog === row.id && imageReference ? (
                          <ImageReferenceDialog
                            imageReference={imageReference}
                            closeDialog={() => setShowImageReferenceDialog(null)}
                          />
                        ) : null}
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
