import {CopilotTextAttacher} from '@github-ui/copilot-chat/utils/copilot-text-attacher'
import {UploadableFileAttachment} from '@github-ui/copilot-chat/utils/uploadable-file-attachment'
import type {CustomCopilotResource, CustomCopilotUploadedTextFileResource} from '@github-ui/custom-copilots/types'
import {forwardRef, useImperativeHandle, useRef} from 'react'

interface FileUploadInputProps {
  onResourcesAdded: (resources: CustomCopilotResource[]) => void
  validateCopilotSpaceResource: (params: {resources: CustomCopilotResource[]}) => Promise<Record<string, number>>
}

export interface FileUploadInputRef {
  addResources: () => void
}

export const FileUploadInput = forwardRef<FileUploadInputRef, FileUploadInputProps>(
  ({onResourcesAdded, validateCopilotSpaceResource}, ref) => {
    const handleFileUpload = async (files: FileList) => {
      const uploadedResources: CustomCopilotUploadedTextFileResource[] = []

      for (const file of Array.from(files)) {
        try {
          if (file.size > CopilotTextAttacher.getAttachmentSizeLimit()) {
            // TODO: show error `File "${file.name}" is too large. Maximum size is 500KB.` - https://github.com/github/copilot-productivity/issues/5965
            continue
          }

          if (!(await CopilotTextAttacher.isAttachable(file))) {
            // TODO: show error `File "${file.name}" is not a supported text file.` - https://github.com/github/copilot-productivity/issues/5965
            continue
          }

          const key = crypto.randomUUID()
          const uploadableAttachment = new UploadableFileAttachment(key, file)
          const copilotChatAttachmentId = await uploadableAttachment.assetId() // Uploads the file

          const resource: CustomCopilotUploadedTextFileResource = {
            id: key, // Used to associate the resource with its validation result. Doesn't need to match the key used in UploadableFileAttachment.
            type: 'uploaded_text_file',
            name: file.name,
            copilotChatAttachmentId,
            markedForDestroy: false,
          }

          uploadedResources.push(resource)
        } catch {
          // TODO: log and show error `Failed to process file "${file.name}":` - https://github.com/github/copilot-productivity/issues/5978
        }
      }

      if (uploadedResources.length > 0) {
        try {
          const validationResult = await validateCopilotSpaceResource({resources: uploadedResources})
          const validatedResources = uploadedResources.map(resource => ({
            ...resource,
            sizePercentage: validationResult[resource.id],
          }))

          onResourcesAdded(validatedResources)
        } catch {
          // TODO: log and show error 'Failed to validate uploaded resources:' - https://github.com/github/copilot-productivity/issues/5978
        }
      }
    }

    const fileInputRef = useRef<HTMLInputElement>(null)
    useImperativeHandle(ref, () => ({addResources: () => fileInputRef.current?.click()}))

    return (
      <input
        data-testid="file-upload-input"
        ref={fileInputRef}
        type="file"
        accept={CopilotTextAttacher.getTextFileExtensions()}
        multiple
        style={{display: 'none'}}
        onChange={e => {
          if (e.target.files && e.target.files.length > 0) {
            void handleFileUpload(e.target.files)
            // Reset the input value to allow the same file to be selected again
            e.target.value = ''
          }
        }}
      />
    )
  },
)

FileUploadInput.displayName = 'FileUploadInput'
