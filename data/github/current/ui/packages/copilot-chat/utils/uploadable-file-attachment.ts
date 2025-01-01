import type {FileAttachment} from '@github-ui/attachments/types'
import {complete, createPolicy, uploadFile} from '@github-ui/attachments/uploadable'
import {resource} from '@github-ui/attachments/util/resource'

import {sendVisionErrorEvent} from './copilot-image-helpers'

// See: UploadPoliciesController#create
const POLICY_URL = '/upload/policies/copilot-chat-attachments'

export interface DotcomFileAttachment extends FileAttachment {
  width?: number
  height?: number
  isLoaded: boolean
  hasError: boolean
  getDimensions(): Promise<{width: number; height: number} | {width: undefined; height: undefined}>
}

async function calculateImageDimensions(
  file: File,
  attachment: {width?: number; height?: number},
): Promise<{width: number; height: number} | {width: undefined; height: undefined}> {
  if (attachment.width !== undefined && attachment.height !== undefined) {
    return {width: attachment.width, height: attachment.height}
  }

  // For non-image files, we resolve with undefined dimensions
  if (!file.type.startsWith('image/')) {
    return {width: undefined, height: undefined}
  }

  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = loadedFileEvent => {
      // This executes asynchronously after the call to readAsDataURL.
      if (!loadedFileEvent.target?.result || typeof loadedFileEvent.target.result !== 'string') {
        resolve({width: undefined, height: undefined})
        return
      }

      const image = new Image()
      image.onload = () => {
        attachment.width = image.width
        attachment.height = image.height
        resolve({width: image.width, height: image.height})
      }
      image.onerror = () => reject(new Error('Failed to load image for dimension extraction'))
      image.src = loadedFileEvent.target.result
    }
    reader.readAsDataURL(file)
  })
}

export class UploadableFileAttachment implements DotcomFileAttachment {
  file: File
  width?: number
  height?: number
  #dimensions: Promise<{width: number; height: number} | {width: undefined; height: undefined}>
  #signal: AbortSignal
  abortController: AbortController
  key: string
  threadID?: string
  isLoaded = false
  hasError = false

  constructor(key: string, file: File, forThreadID?: string) {
    this.file = file
    this.abortController = new AbortController()
    this.#signal = this.abortController.signal
    this.key = key
    this.#dimensions = this.getDimensions()
    this.threadID = forThreadID
  }

  #resource = resource(async () => {
    const policy = await createPolicy(
      {
        name: this.file.name,
        size: String(this.file.size),
        // eslint-disable-next-line camelcase
        content_type: this.file.type,
        // eslint-disable-next-line camelcase
        thread_id: this.threadID,
      },
      POLICY_URL,
      this.#signal,
    )
    await uploadFile(this.file, policy, this.#signal)
    const asset = await complete(policy, this.#signal)
    const dimensions = await this.#dimensions
    this.width = dimensions.width
    this.height = dimensions.height
    this.isLoaded = true
    return asset
  })

  prefetch() {
    return this.#resource.load()
  }

  get previewUrl() {
    return this.#resource.read().href
  }

  /**
   * Gets the asset ID for the uploaded file.
   *
   * @returns A promise that resolves with the asset ID
   */
  async assetId() {
    const asset = await this.#resource.load()
    return asset.id
  }

  /**
   * Gets the durable asset URL for the file.
   *
   * @returns A promise that resolves with the asset url
   */
  async url() {
    const asset = await this.#resource.load()
    return asset.href
  }

  async getDimensions(): Promise<{width: number; height: number} | {width: undefined; height: undefined}> {
    return calculateImageDimensions(this.file, this)
  }
}

export class Base64FileAttachment implements DotcomFileAttachment {
  key: string
  file: File
  width?: number
  height?: number
  isLoaded = false
  hasError = false

  constructor(key: string, file: File) {
    this.file = file
    this.key = key
  }

  #resource = resource<string>(async () => {
    return new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = loadedFileEvent => {
        // This executes asynchronously after the call to readAsDataURL.
        if (!loadedFileEvent.target || !loadedFileEvent.target.result) return
        const result = loadedFileEvent.target.result
        if (typeof result !== 'string') return
        const base64String = result.split(',')[1] // Strip the data URL prefix
        if (base64String) {
          if (base64String.length > 500_000) {
            const errorMessage = 'Only images below 500KB are supported during this preview period'
            sendVisionErrorEvent('size_limit_exceeded', {size: base64String.length})
            const error = new Error(errorMessage)
            error.name = 'FileSizeError'
            reject(error)
            this.hasError = true
            return
          }

          const image = new Image()
          image.onload = () => {
            this.width = image.width
            this.height = image.height
          }
          // Note that this is using result, not base64String, because result is the full data URL
          image.src = result

          resolve(reader.result as string)
          this.isLoaded = true
        }
      }

      reader.onerror = fileErrorEvent => {
        // This executes asynchronously after the call to readAsDataURL.
        if (fileErrorEvent.target) {
          const error = fileErrorEvent.target.error
          if (error) {
            sendVisionErrorEvent(error.name, {message: error.message})
            reject(error)
            this.hasError = true
            return
          }
        }
        reject(new Error("Couldn't read the file due to an unknown error"))
        this.hasError = true
      }

      reader.readAsDataURL(this.file)
    })
  })

  prefetch() {
    return this.#resource.load()
  }

  get previewUrl() {
    // NOTE: In the future, if the file is not an image, perhaps we can return a generic preview image
    return this.#resource.read()
  }

  url() {
    return this.#resource.load()
  }

  async getDimensions(): Promise<{width: number; height: number} | {width: undefined; height: undefined}> {
    return calculateImageDimensions(this.file, this)
  }
}
