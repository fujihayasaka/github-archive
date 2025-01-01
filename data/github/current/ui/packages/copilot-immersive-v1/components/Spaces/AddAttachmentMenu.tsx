import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {MultiFilePicker} from '@github-ui/custom-copilots/components/MultiFilePicker'
import type {CustomCopilotResource, GitHubFileFormData} from '@github-ui/custom-copilots/types'
import {FileCodeIcon, PasteIcon, PlusIcon, UploadIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useRef, useState} from 'react'

import {FileUploadInput, type FileUploadInputRef} from './FileUploadInput'
import {GitHubUrlDialog} from './GitHubUrlDialog'
import {useGetCopilotSpaceResourceSizes} from './hooks/use-get-copilot-space-resource-sizes'
import {TextFileDialog} from './TextFileDialog'

interface AddAttachmentMenuProps {
  children: React.ReactElement
  findFileWorkerPath: string
  onResourcesAdded: (resources: CustomCopilotResource[]) => void
  owner: string | undefined
  sizePercentage?: number
  resourcesToSave: CustomCopilotResource[]
}

export const AddAttachmentMenu = ({
  children,
  findFileWorkerPath,
  onResourcesAdded,
  owner,
  sizePercentage,
  resourcesToSave,
}: AddAttachmentMenuProps) => {
  const [showAddTextFileDialog, setShowAddTextFileDialog] = useState(false)
  const [showMultiFilePicker, setShowMultiFilePicker] = useState(false)
  const [showAddGitHubUrlDialog, setShowAddGitHubUrlDialog] = useState(false)
  const fileUploadInputRef = useRef<FileUploadInputRef>(null)
  const {getCopilotSpaceResourceSizes: validateCopilotSpaceResource} = useGetCopilotSpaceResourceSizes()

  const saveGitHubResources = async (resources: GitHubFileFormData[]) => {
    if (resources.length === 0) {
      setShowMultiFilePicker(false)
      return
    }

    const validationResult = await validateCopilotSpaceResource({
      resources: resources as CustomCopilotResource[],
    })
    const hydratedResources = resources.map(resource => {
      const resourceId = resource.id
      const fileSizePercentage = validationResult[resourceId]
      return {
        ...resource,
        fileExists: true,
        markedForDestroy: false,
        sizePercentage: fileSizePercentage,
      }
    })
    onResourcesAdded(hydratedResources)
    setShowMultiFilePicker(false)
  }
  const attachmentButtonRef = useRef<HTMLButtonElement>(null)
  const issuesPrsEnabled = copilotFeatureFlags.spacesIssuesPrsEnabled
  const fileUploadsEnabled = copilotFeatureFlags.customCopilotsFileUploads

  return (
    <>
      {fileUploadsEnabled && (
        <FileUploadInput
          ref={fileUploadInputRef}
          onResourcesAdded={onResourcesAdded}
          validateCopilotSpaceResource={validateCopilotSpaceResource}
        />
      )}
      <ActionMenu anchorRef={attachmentButtonRef}>
        <ActionMenu.Anchor>{children}</ActionMenu.Anchor>
        <ActionMenu.Overlay align="end" width={issuesPrsEnabled ? 'small' : undefined}>
          <ActionList>
            <ActionList.Item onSelect={() => setShowMultiFilePicker(true)}>
              <ActionList.LeadingVisual>
                <FileCodeIcon />
              </ActionList.LeadingVisual>
              Add files, folders...
            </ActionList.Item>
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
            {fileUploadsEnabled && (
              <ActionList.Item onSelect={() => fileUploadInputRef.current?.addResources()}>
                <ActionList.LeadingVisual>
                  <UploadIcon />
                </ActionList.LeadingVisual>
                Upload from computer
              </ActionList.Item>
            )}
            {issuesPrsEnabled && (
              <ActionList.Item onSelect={() => setShowAddGitHubUrlDialog(true)}>
                <ActionList.LeadingVisual>
                  <PasteIcon />
                </ActionList.LeadingVisual>
                Add via GitHub URL...
              </ActionList.Item>
            )}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {showAddTextFileDialog && (
        <TextFileDialog
          sizePercentage={sizePercentage}
          onClose={() => setShowAddTextFileDialog(false)}
          onSave={resource => onResourcesAdded([resource])}
        />
      )}
      {showMultiFilePicker && (
        <MultiFilePicker
          formData={[]}
          onCancel={() => setShowMultiFilePicker(false)}
          onSave={saveGitHubResources}
          findFileWorkerPath={findFileWorkerPath}
          attachmentButtonRef={attachmentButtonRef}
          owner={owner}
          openRepoPanel
        />
      )}
      {showAddGitHubUrlDialog && (
        <GitHubUrlDialog
          onClose={() => setShowAddGitHubUrlDialog(false)}
          onSave={(resources: CustomCopilotResource[]) => onResourcesAdded(resources)}
          resourcesToSave={resourcesToSave}
          owner={owner}
        />
      )}
    </>
  )
}
