import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CustomCopilotFreeTextResource, CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {FileCodeIcon, FileIcon, KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Stack, Truncate, VisuallyHidden} from '@primer/react'
import {DataTable, Table} from '@primer/react/experimental'
import {useState} from 'react'

import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'
import {TextFileDialog} from './TextFileDialog'

interface ReferencesTableProps {
  copilotSpace: CustomCopilot
}

export function ReferencesTable({copilotSpace}: ReferencesTableProps) {
  const {upsertCopilotSpace} = useUpsertCopilotSpace(copilotSpace.id)

  async function deleteResource(resource: CustomCopilotResource) {
    await upsertCopilotSpace({
      resources: [
        {
          ...resource,
          markedForDestroy: true,
        },
      ],
    })
  }

  return (
    <Table.Container>
      <DataTable
        aria-labelledby="references-title"
        cellPadding="normal"
        data={copilotSpace.resources}
        columns={[
          {
            id: 'id',
            header: 'Name',
            rowHeader: true,
            renderCell: row => {
              switch (row.type) {
                case 'github_file': {
                  const path = row.filePath.split('/')
                  const fileName = path.pop()!
                  const filePath = [row.nwo, ...path].join('/')
                  return (
                    <Stack direction="horizontal" align="center" gap="normal">
                      <FileCodeIcon size={16} />
                      <Stack gap="none">
                        <span className="text-normal f5">{fileName}</span>
                        <div>
                          <Truncate title={filePath} maxWidth={300} className="text-normal fgColor-muted">
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
                      <FileIcon size={16} />
                      <div>
                        <Truncate title={row.name} maxWidth={300} className="text-normal f5">
                          {row.name}
                        </Truncate>
                      </div>
                    </Stack>
                  )
                default:
                  // log error Unsupported resource type
                  return null
              }
            },
          },
          {
            id: 'actions',
            header: () => <VisuallyHidden>Actions</VisuallyHidden>,
            maxWidth: 'auto',
            align: 'end',
            renderCell: row => {
              return (
                <RowActions copilotSpaceId={copilotSpace.id} row={row} onEdit={() => {}} onDelete={deleteResource} />
              )
            },
          },
        ]}
      />
    </Table.Container>
  )
}

interface RowActionsProps {
  copilotSpaceId: CustomCopilot['id']
  row: CustomCopilotResource
  onEdit: (row: CustomCopilotResource) => void
  onDelete: (row: CustomCopilotResource) => void
}

const RowActions = ({copilotSpaceId, row, onDelete}: RowActionsProps) => {
  const [editResourceDialog, setEditResourceDialog] = useState<CustomCopilotFreeTextResource | null>(null)

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton
            aria-label={`Resource actions`}
            title={`Resource actions`}
            icon={KebabHorizontalIcon}
            variant="invisible"
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
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
            <ActionList.Item
              variant="danger"
              onSelect={() => {
                void onDelete(row)
              }}
            >
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
          copilotSpaceId={copilotSpaceId}
          resource={editResourceDialog}
          onClose={() => {
            setEditResourceDialog(null)
          }}
        />
      )}
    </>
  )
}
