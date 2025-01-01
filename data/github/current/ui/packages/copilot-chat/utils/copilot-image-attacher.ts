import {sendEvent} from '@github-ui/hydro-analytics'

import {makePlaceholderReference} from './copilot-chat-helpers'
import type {CopilotChatManager} from './copilot-chat-manager'
import type {CopilotChatState} from './copilot-chat-reducer'
import type {CopilotChatModel, CustomCopilotId, ImageReference, LoadingReference} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {sendVisionErrorEvent} from './copilot-image-helpers'
import {Base64FileAttachment, type DotcomFileAttachment, UploadableFileAttachment} from './uploadable-file-attachment'

// Should be limited to images that are supported by our models and other dependencies.
// We pull the types from the model capabilities and filter for these types.
// NOTE - when we update this, we need to also update our Copilot::ChatAttachment::CHAT_SPECIFIC_CONTENT_TYPES
const ACCEPTED_BASE64_IMAGE_FILE_MIME_TYPES: string[] = ['image/gif', 'image/jpeg', 'image/png', 'image/webp']

const DOTCOM_CHAT_ATTACHMENT_LIMIT = 1
const DOTCOM_CHAT_ATTACHMENT_LIMIT_MULTIPLE = 4
const DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT = 3.75 * 1000 * 1024 // Claude only supports up to 3.75MB
const DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT_BASE64 = 500 * 1024 // 500KB

export class CopilotImageAttacher {
  private state: CopilotChatState
  private manager: CopilotChatManager

  public constructor(state: CopilotChatState, manager: CopilotChatManager) {
    this.state = state
    this.manager = manager
  }

  public static getAllowedImageFileExtensions(model: CopilotChatModel): string {
    return this.getFileExtensions(model).join(',')
  }

  public static isTypeAllowed(itemType: string, model: CopilotChatModel): boolean {
    itemType = itemType.toLowerCase()
    const mimeTypes = this.getMimeTypes(model)
    return mimeTypes.includes(itemType)
  }

  public static getAllowedFiles(files: File[], model: CopilotChatModel): [allowedImages: File[], otherFiles: File[]] {
    const [allowedImages, otherFiles] = files.reduce(
      ([images, other]: [File[], File[]], file) =>
        this.isTypeAllowed(file.type, model) ? [[...images, file], other] : [images, [...other, file]],
      [[], []],
    )
    return [allowedImages, otherFiles]
  }

  public static getAttachmentLimit(): number {
    return copilotFeatureFlags.attachMultipleImages
      ? DOTCOM_CHAT_ATTACHMENT_LIMIT_MULTIPLE
      : DOTCOM_CHAT_ATTACHMENT_LIMIT
  }

  public static getAttachmentSizeLimit(): number {
    if (copilotFeatureFlags.dotcomChatFileUpload) {
      return DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT
    }
    return DOTCOM_CHAT_ATTACHMENT_SIZE_LIMIT_BASE64
  }

  public static makeImageReference(file: File, threadIDToAssociate: string): ImageReference {
    const referenceId = crypto.randomUUID()
    let attachment: DotcomFileAttachment
    if (copilotFeatureFlags.dotcomChatFileUpload) {
      attachment = new UploadableFileAttachment(referenceId, file, threadIDToAssociate)
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

  /**
   * Adds image attachments to the current chat thread. If no thread is selected and file upload is enabled,
   * a new thread will be created.
   *
   * @param files - The list of image files to attach.
   * @param uploadType - The type of upload action (e.g., 'drag', 'paste', 'menu', or 'unknown').
   * @param customCopilotId - (Optional) A custom Copilot ID to associate with the thread being created.
   * @param preventThreadSelection - (Optional) If true, prevents the selection of the thread being created. By default, it is false.
   */
  public async addImageAttachments(
    files: File[],
    uploadType: 'drag' | 'paste' | 'menu' | 'unknown' = 'unknown',
    customCopilotId?: CustomCopilotId | null,
    preventThreadSelection = false,
  ): Promise<ImageReference[]> {
    if (files.length === 0) return []
    let thread = null
    let threadIDToAssociate = this.state.selectedThreadID
    const pendingThreadId = this.manager.getPendingThreadId(customCopilotId)

    if (customCopilotId && !threadIDToAssociate && pendingThreadId) {
      threadIDToAssociate = pendingThreadId
    }

    if (!threadIDToAssociate && copilotFeatureFlags.dotcomChatFileUpload) {
      try {
        thread = await this.manager.createThread(customCopilotId, preventThreadSelection)
        threadIDToAssociate = thread.id
      } catch (error) {
        let errorMessage = 'An error occurred creating the thread. Sending a single message should create a new thread.'
        if (error instanceof Error) {
          errorMessage ||= error.message
        }

        this.manager.addAmbientError(errorMessage)
        throw new Error(errorMessage)
      }
    }

    const imageReferenceCount = this.state.currentReferences.filter(reference => reference.type === 'image').length
    const imageLimit = CopilotImageAttacher.getAttachmentLimit()
    if (imageReferenceCount + files.length > imageLimit) {
      const errorMessage = copilotFeatureFlags.attachMultipleImages
        ? `You can add up to ${imageLimit} image files per message.`
        : 'Only one image can be uploaded at a time'
      this.manager.addAmbientError(errorMessage)
      sendVisionErrorEvent('file_limit_reached')
      return []
    }

    const usingUpload = copilotFeatureFlags.dotcomChatFileUpload
    const fileLimitErrorMessage = `Only images below ${usingUpload ? '3.75MB' : '500KB'} are supported${
      usingUpload ? '' : ' during this preview period'
    }`

    const newReferences: ImageReference[] = []
    const validFilesWithPlaceholders: Array<{file: File; placeholder: LoadingReference; reference: ImageReference}> = []

    for (const file of files) {
      // Valid file types: attempts to bypass the file types allowed by the input element can occur, so we should check here as well
      if (!CopilotImageAttacher.isTypeAllowed(file.type, this.state.model)) {
        sendVisionErrorEvent('included_unsupported_file', {fileTypes: file.type, uploadType})
        return []
      }

      // Base64 encoding always increases the size of a file, so it should be safe to return here in both upload flows.
      // We also check the size after encoding, but returning earlier here helps avoid some UI flickering.
      if (file.size > CopilotImageAttacher.getAttachmentSizeLimit()) {
        this.manager.addAmbientError(fileLimitErrorMessage)
        sendVisionErrorEvent('size_limit_exceeded', {size: file.size})
        return []
      }

      if (threadIDToAssociate == null) {
        // Not an expected case, but giving the user directions to help them unblock themselves.
        this.manager.addAmbientError('Please manually create a thread before uploading an image')
        throw new Error('ThreadID resolution for image attachment is not functioning properly')
      }

      const reference = CopilotImageAttacher.makeImageReference(file, threadIDToAssociate)

      // Claude models reject images with any dimension exceeding 8000 pixels
      if (this.state.model.id.startsWith('claude') && this.state.model.capabilities.supports.vision) {
        const dimensions = await reference.attachment.getDimensions()
        if (dimensions.width && dimensions.height) {
          if (dimensions.width > 8000 || dimensions.height > 8000) {
            this.manager.addAmbientError(
              'The image you uploaded exceeds the maximum allowed dimensions for Claude models. Please try again with another model.',
            )
            sendVisionErrorEvent('dimension_limit_exceeded', {
              width: dimensions.width,
              height: dimensions.height,
            })
            continue
          }
        }
      }

      const placeholder = makePlaceholderReference(file)
      this.manager.addReference(placeholder, 'image-attacher')
      if (validFilesWithPlaceholders.length === 0) {
        this.manager.dispatch({type: 'WAITING_ON_ATTACHMENT', loading: true})
      }
      validFilesWithPlaceholders.push({file, placeholder, reference})
    }

    // Load each of the attachments
    await Promise.all(
      validFilesWithPlaceholders.map(async ({file, placeholder, reference}) => {
        try {
          await reference.attachment.prefetch()
          this.manager.setImageAttachmentUploaded(reference.id, reference.attachment)
          this.manager.replaceReference(placeholder, reference)
          sendEvent('dotcom_chat.vision.image_added', {uploadType})
          newReferences.push(reference)
        } catch (error) {
          this.manager.removeReference(placeholder)

          const UNEXPECTED_ERROR = `An unexpected error occurred while reading the file`
          if (typeof error === 'string') {
            this.manager.addAmbientError(`An error occurred uploading the attachment ${file.name}`)
            sendVisionErrorEvent('ErrorString', {message: error})
            throw Error(error)
          } else if (error instanceof Error) {
            sendVisionErrorEvent(error.name, {message: error.message})
            if (error.name === 'FileSizeError') {
              this.manager.addAmbientError(fileLimitErrorMessage)
            } else if (error.name === 'GenericServerError' && error.message.includes('Error creating policy')) {
              this.manager.addAmbientError(UNEXPECTED_ERROR)
            } else {
              this.manager.addAmbientError(UNEXPECTED_ERROR)
              throw error
            }
          } else {
            this.manager.addAmbientError(UNEXPECTED_ERROR)
            throw error
          }
        }
      }),
    ).finally(() => {
      this.manager.dispatch({type: 'WAITING_ON_ATTACHMENT', loading: false})
    })

    // If we created a thread but don't want to select it, we need to set the pending thread ID
    // so that the thread can be found later.
    // It's necessary to store it only in case no errors happened
    if (preventThreadSelection && customCopilotId && thread) {
      this.manager.setPendingThreadId(thread.id, customCopilotId)
    }

    return newReferences
  }
}
