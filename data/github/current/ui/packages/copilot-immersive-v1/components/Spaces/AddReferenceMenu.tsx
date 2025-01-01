import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {MultiFilePicker} from '@github-ui/custom-copilots/components/MultiFilePicker'
import type {GitHubFileFormData} from '@github-ui/custom-copilots/types'
import {FileCodeIcon, PlusIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useState} from 'react'

import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'
import {TextFileDialog} from './TextFileDialog'

interface AddReferenceMenuProps {
  copilotSpace: CustomCopilot
  children: React.ReactElement
  findFileWorkerPath: string
}

export const AddReferenceMenu = ({children, copilotSpace, findFileWorkerPath}: AddReferenceMenuProps) => {
  const [showAddTextFileDialog, setShowAddTextFileDialog] = useState(false)
  const [showMultiFilePicker, setShowMultiFilePicker] = useState(false)

  const {upsertCopilotSpace} = useUpsertCopilotSpace(copilotSpace.id)

  // uncomment when we support uploading files from the computer
  // see: @github-ui/use-unified-file-select
  // const {clickTargetProps} = useUnifiedFileSelect({
  //   acceptedFileTypes: ['text/plain', 'application/pdf', 'text/csv'],
  //   // multi: false,
  //   onSelect: files => {
  //     // eslint-disable-next-line no-console
  //     console.log('Selected files:', files)
  //   },
  // })

  const saveGitHubResources = async (resources: GitHubFileFormData[]) => {
    await upsertCopilotSpace({
      resources: resources.map(resource => ({
        ...resource,
        markedForDestroy: false,
      })),
    })

    setShowMultiFilePicker(false)
  }

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>{children}</ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList>
            <ActionList.Item
              onSelect={() => {
                setShowMultiFilePicker(true)
              }}
            >
              <ActionList.LeadingVisual>
                <FileCodeIcon />
              </ActionList.LeadingVisual>
              Add files, folders...
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item
              onSelect={() => {
                setShowAddTextFileDialog(true)
              }}
            >
              <ActionList.LeadingVisual>
                <PlusIcon />
              </ActionList.LeadingVisual>
              Add a text file
            </ActionList.Item>
            {/* <ActionList.Item onSelect={e => clickTargetProps.onClick(e as React.MouseEvent)}>
              <ActionList.LeadingVisual>
                <UploadIcon />
              </ActionList.LeadingVisual>
              Upload from computer
            </ActionList.Item> */}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {showAddTextFileDialog && (
        <TextFileDialog copilotSpaceId={copilotSpace.id} onClose={() => setShowAddTextFileDialog(false)} />
      )}
      {showMultiFilePicker && (
        <MultiFilePicker
          formData={[]}
          onCancel={() => {
            setShowMultiFilePicker(false)
          }}
          onSave={saveGitHubResources}
          findFileWorkerPath={findFileWorkerPath}
        />
      )}
    </>
  )
}
