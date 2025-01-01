import type {ImageDefinition, ImageVersion} from '../types/types'
import {ActionList, ActionMenu, IconButton, VisuallyHidden, Label, Text, Button} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {DataTable, Table} from '@primer/react/experimental'

import {useState, useEffect} from 'react'
import {DeleteCuratedImageVersionDialog} from './DeleteCuratedImageVersionDialog'
import {updateCuratedImageVersion} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {curatedImageDetailsUrl, curatedImageVersionDetailsUrl} from '../helpers/urls'
import {useNavigate} from '@github-ui/use-navigate'
import {ImageVersionEnabledState} from './ImageVersionEnabledState'

interface CuratedImageVersionsTableProps {
  curatedImageVersions: ImageVersion[]
  curatedImage: ImageDefinition
}

export function CuratedImageVersionsTable(props: CuratedImageVersionsTableProps) {
  const [showDeleteDialog, setShowDeleteDialog] = useState<number | null>(null)
  const flashBanner = useFlashBannerState()
  const navigate = useNavigate()

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
      flashBanner.showInfo('Image version has been updated')
      window.location.assign(curatedImageDetailsUrl(props.curatedImage.id))
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
        <Table.Title as="h2" id="curated-images">
          Image Versions ({props.curatedImageVersions.length})
        </Table.Title>
        <Table.Actions>
          {props.curatedImage.latestVersion && (
            <Button
              variant="default"
              size="small"
              onClick={() => navigate(curatedImageVersionDetailsUrl(props.curatedImage.id, 'latest'))}
            >
              Latest version: <strong>{props.curatedImage.latestVersion}</strong>
            </Button>
          )}
        </Table.Actions>
        <DataTable
          data={props.curatedImageVersions}
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
                    {row.version} {row.version === props.curatedImage.latestVersion && <Label>Latest</Label>}
                  </Text>
                )
              },
            },
            {
              header: 'State',
              field: 'state',
            },
            {
              header: 'VMGen',
              field: 'vmGeneration',
            },
            {
              header: 'OsState',
              field: 'osState',
            },
            {
              header: 'SizeGB',
              field: 'sizeGb',
            },
            {
              header: 'Enabled',
              field: 'enabled',
              renderCell: row => <ImageVersionEnabledState imageVersion={row} />,
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
                          onSelect={() => navigate(curatedImageVersionDetailsUrl(props.curatedImage.id, row.version))}
                          onClick={() => navigate(curatedImageVersionDetailsUrl(props.curatedImage.id, row.version))}
                        >
                          Details
                        </ActionList.Item>
                        <ActionList.Item onSelect={() => handleEnableDisable(row)}>
                          {row.enabled ? 'Disable' : 'Enable'}
                        </ActionList.Item>
                        {deleteImageVersionActionButton(row)}
                        {showDeleteDialog === row.id && (
                          <DeleteCuratedImageVersionDialog
                            closeDialog={() => setShowDeleteDialog(null)}
                            curatedImageVersion={row}
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
