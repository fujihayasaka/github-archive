import {sendEvent} from '@github-ui/hydro-analytics'

import type {CopilotAutocompleteManager} from './copilot-autocompletions'
import type {CopilotChatManager} from './copilot-chat-manager'
import type {CopilotChatState} from './copilot-chat-reducer'
import type {CopilotChatModel, ImageReference} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {Base64FileAttachment, type DotcomFileAttachment, UploadableFileAttachment} from './uploadable-file-attachment'

// Should be limited to images that we know we can base64 encode and are supported by our models.
// We pull the types from the model capabilities and filter for these types.
const ACCEPTED_BASE64_IMAGE_FILE_MIME_TYPES: string[] = ['image/gif', 'image/jpeg', 'image/png', 'image/webp']

const DOTCOM_CHAT_ATTACHMENT_LIMIT = 1
const DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT = 3.75 * 1000 * 1024 // Claude only supports up to 3.75MB
const DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT_BASE64 = 500 * 1024 // 500KB

export class CopilotImageAttacher {
  private state: CopilotChatState
  private manager: CopilotChatManager
  private autocomplete: CopilotAutocompleteManager

  public constructor(state: CopilotChatState, manager: CopilotChatManager, autocomplete: CopilotAutocompleteManager) {
    this.state = state
    this.manager = manager
    this.autocomplete = autocomplete
  }

  public static getAllowedImageFileExtensions(model: CopilotChatModel): string {
    return this.getFileExtensions(model).join(',')
  }

  public static isTypeAllowed(itemType: string, model: CopilotChatModel): boolean {
    itemType = itemType.toLowerCase()
    const mimeTypes = this.getMimeTypes(model)
    return mimeTypes.includes(itemType)
  }

  public static getAttachmentLimit(): number {
    return DOTCOM_CHAT_ATTACHMENT_LIMIT
  }

  public static getAttachmentSizeLimit(): number {
    if (copilotFeatureFlags.dotcomChatFileUpload) {
      return DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT
    }
    return DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT_BASE64
  }

  public static makeImageReference(file: File, signal: AbortSignal): ImageReference {
    const referenceId = crypto.randomUUID()
    let attachment: DotcomFileAttachment
    if (copilotFeatureFlags.dotcomChatFileUpload) {
      attachment = new UploadableFileAttachment(referenceId, file, signal)
    }
    attachment ||= new Base64FileAttachment(referenceId, file)

    return {
      id: referenceId,
      attachment,
      type: 'image',
      name: file.name || 'Image',
    }
  }

  private static getFileExtensions(model: CopilotChatModel): string[] {
    const extensions = this.getMimeTypes(model).map(type => `.${type.split('/')[1]}`)

    if (extensions.includes('.jpeg')) {
      extensions.push('.jpg')
    }

    return extensions
  }

  private static getMimeTypes(model: CopilotChatModel): string[] {
    if (model.capabilities.limits.vision) {
      const supportedTypes = model.capabilities.limits.vision.supported_media_types
      // for now, we can only return supported types that can be base 64 encoded. Remove once we stop
      // encoding images as base 64
      return supportedTypes.filter(type => ACCEPTED_BASE64_IMAGE_FILE_MIME_TYPES.includes(type))
    }

    return []
  }

  public async addImageAttachment(file: File, signal: AbortSignal, uploadType?: 'drag' | 'paste' | 'menu' | 'unknown') {
    const hasAnImageReferenceAlready = !!this.state.currentReferences.find(x => x.type === 'image')
    if (hasAnImageReferenceAlready) {
      const errorMessage = 'Only one image can be uploaded at a time'
      this.manager.addAmbientError(errorMessage)
      sendEvent('dotcom_chat.vision.error', {type: 'file_limit_reached'})
      return
    }

    // Base64 encoding always increases the size of a file, so it should be safe to return here in both upload flows.
    // We also check the size after encoding, but returning earlier here helps avoid some UI flickering.
    if (file.size > CopilotImageAttacher.getAttachmentSizeLimit()) {
      const usingUpload = copilotFeatureFlags.dotcomChatFileUpload
      const errorMessage = `Only images below ${usingUpload ? '3.75MB' : '500KB'} are supported${
        usingUpload ? '' : ' during this preview period'
      }`
      this.manager.addAmbientError(errorMessage)
      sendEvent('dotcom_chat.vision.error', {type: 'size_limit_exceeded', size: file.size})
      return
    }

    // We want to create and add the image reference before the attachment is fully loaded.
    // This lets us display an in-progress reference to the user
    const reference = CopilotImageAttacher.makeImageReference(file, signal)
    await this.autocomplete.addToReferences(reference, this.state)

    try {
      await reference.attachment.prefetch()
    } catch (error) {
      if (typeof error === 'string') {
        this.manager.addAmbientError('An error occurred uploading the attachment')
      } else if (error instanceof Error) {
        if (error.name === 'FileSizeError') {
          this.manager.addAmbientError('Only images below 500KB are supported during this preview period')
        } else {
          this.manager.addAmbientError(`An unexpected error occurred while reading the file`)
          this.manager.removeReference(reference)
          throw error
        }
      }
      this.manager.removeReference(reference)
      return
    }
    this.manager.setImageAttachmentUploaded(reference.id, reference.attachment)
    uploadType ||= 'unknown'
    sendEvent('dotcom_chat.vision.image_added', {uploadType})
  }
}
