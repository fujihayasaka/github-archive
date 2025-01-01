import {generateGitHubFileMetadata} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {CustomCopilotFreeTextResource, CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {AlertIcon, KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Link, Stack, Truncate, VisuallyHidden} from '@primer/react'
import {type Column, DataTable, Table} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useMemo, useState} from 'react'

import {AttachmentIcon} from './AttachmentIcon'
import styles from './ReferencesTable.module.css'
import {TextFileDialog} from './TextFileDialog'
import {uniqueBy} from './utils/unique-by'

interface ReferencesTableProps {
  resources: CustomCopilotResource[]
  onDeleteResource: (resource: CustomCopilotResource) => void
  onUpdateResource: (resource: CustomCopilotResource) => void
  sizePercentage?: number
}

export function ReferencesTable({resources, onDeleteResource, onUpdateResource, sizePercentage}: ReferencesTableProps) {
  const uniqueResources = useMemo(() => uniqueBy(resources, getUniqueKey), [resources])

  const columns = useMemo(() => {
    const columnsProps: Array<Column<CustomCopilotResource>> = [
      {
        id: 'id',
        header: 'Name',
        rowHeader: true,
        renderCell: row => {
          switch (row.type) {
            case 'github_file': {
              const {filePath, fileName, fileUrl} = generateGitHubFileMetadata(row)

              return (
                <Stack direction="horizontal" align="center" gap="normal">
                  <AttachmentIcon attachment={row} className="fgColor-muted" />
                  <Stack gap="none">
                    <div>
                      {row.fileExists ? (
                        <Truncate title={fileName} className={clsx(styles.referenceTitle, 'f5 text-normal')}>
                          <Link rel="noopener" target="_blank" href={fileUrl} className={styles.referenceTitleLink}>
                            {fileName}
                          </Link>
                        </Truncate>
                      ) : (
                        <Truncate title={fileName} className={clsx(styles.referenceTitle, 'f5 text-normal')}>
                          {fileName}
                        </Truncate>
                      )}
                    </div>
                    <div>
                      <Truncate title={filePath} className={clsx(styles.referenceTitle, 'fgColor-muted')}>
                        {filePath}
                      </Truncate>
                    </div>
                  </Stack>
                </Stack>
              )
            }
            case 'free_text':
              return (
                <Stack direction="horizontal" align="center" gap="normal">
                  <AttachmentIcon attachment={row} className="fgColor-muted" />
                  <div>
                    <Truncate title={row.name} maxWidth={300} className={clsx(styles.referenceTitle, 'f5 text-normal')}>
                      {row.name}
                    </Truncate>
                  </div>
                </Stack>
              )
            case 'uploaded_text_file':
              return (
                <Stack direction="horizontal" align="center" gap="normal">
                  <AttachmentIcon attachment={row} className="fgColor-muted" />
                  <div>
                    <Truncate title={row.name} maxWidth={300} className={clsx(styles.referenceTitle, 'f5 text-normal')}>
                      {row.name}
                    </Truncate>
                  </div>
                </Stack>
              )
            case 'github_pull_request':
            case 'github_issue':
              return (
                <Stack direction="horizontal" align="center" gap="normal">
                  <span>
                    <AttachmentIcon attachment={row} className="fgColor-success" />
                  </span>
                  <Stack gap="none">
                    <div>
                      <Truncate title={row.title || ''} className={clsx(styles.referenceTitle, 'f5 text-bold')}>
                        <Link rel="noopener" target="_blank" href={row.url} className={styles.referenceTitleLink}>
                          {row.title} <span className="fgColor-muted text-light">{`#${row.number}`}</span>
                        </Link>
                      </Truncate>
                    </div>
                    <div>
                      <Truncate title={row.nwo || ''} className={clsx(styles.referenceTitle, 'fgColor-muted')}>
                        {row.nwo}
                      </Truncate>
                    </div>
                  </Stack>
                </Stack>
              )
            default:
              // log error Unsupported resource type
              return null
          }
        },
      },
      {
        id: 'size',
        header: 'Size',
        align: 'end',
        maxWidth: 'auto',
        width: 'growCollapse',
        renderCell: row => {
          return (
            <span className="fgColor-muted">
              {row.sizePercentage && row.sizePercentage < 1 ? '<1%' : `${Math.round(row.sizePercentage || 0)}%`}
            </span>
          )
        },
      },
      {
        id: 'actions',
        header: () => <VisuallyHidden>Actions</VisuallyHidden>,
        maxWidth: 'auto',
        align: 'end',
        renderCell: row => {
          const shouldShowWarning = row.type === 'github_file' && !row.fileExists

          return (
            <>
              {shouldShowWarning && (
                <IconButton
                  className={styles.warningIcon}
                  icon={AlertIcon}
                  variant="invisible"
                  size="small"
                  aria-label="This file no longer exists"
                />
              )}

              <RowActions
                row={row}
                onEdit={onUpdateResource}
                onDelete={onDeleteResource}
                sizePercentage={sizePercentage}
              />
            </>
          )
        },
      },
    ]

    return columnsProps
  }, [onDeleteResource, onUpdateResource, sizePercentage])

  return (
    <Table.Container>
      <DataTable aria-labelledby="references-title" cellPadding="normal" data={uniqueResources} columns={columns} />
    </Table.Container>
  )
}

interface RowActionsProps {
  row: CustomCopilotResource
  onEdit: (updatedResource: CustomCopilotResource) => void
  onDelete: (row: CustomCopilotResource) => void
  sizePercentage?: number
}

const RowActions = ({row, onDelete, onEdit, sizePercentage}: RowActionsProps) => {
  const [editResourceDialog, setEditResourceDialog] = useState<CustomCopilotFreeTextResource | null>(null)

  let attachmentName = ''
  switch (row.type) {
    case 'github_pull_request':
    case 'github_issue':
      attachmentName = row.title
      break
    case 'github_file':
      attachmentName = row.filePath
      break
    case 'free_text':
    case 'uploaded_text_file':
      attachmentName = row.name
      break
  }

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton
            aria-label={`Attachment actions: ${attachmentName}`}
            title={`Attachment actions`}
            icon={KebabHorizontalIcon}
            variant="invisible"
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay align="end">
          <ActionList>
            {row.type === 'free_text' && (
              <>
                <ActionList.Item onSelect={() => setEditResourceDialog(row)}>
                  <ActionList.LeadingVisual>
                    <PencilIcon />
                  </ActionList.LeadingVisual>
                  Edit
                </ActionList.Item>
              </>
            )}
            <ActionList.Item variant="danger" onSelect={() => onDelete(row)}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {editResourceDialog && (
        <TextFileDialog
          sizePercentage={sizePercentage}
          resource={editResourceDialog}
          onSave={onEdit}
          onClose={() => setEditResourceDialog(null)}
        />
      )}
    </>
  )
}

const getUniqueKey = (resource: CustomCopilotResource): string => {
  switch (resource.type) {
    case 'github_file':
      return `${resource.repositoryId}@${resource.filePath}`
    case 'github_issue':
    case 'github_pull_request':
      return resource.url
    default:
      return resource.id
  }
}
