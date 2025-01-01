import type {FileAttachment} from '@github-ui/attachments/types'
import {complete, createPolicy, uploadFile} from '@github-ui/attachments/uploadable'
import {resource} from '@github-ui/attachments/util/resource'
import {sendEvent} from '@github-ui/hydro-analytics'
import {verifiedFetch} from '@github-ui/verified-fetch'

// See: UploadPoliciesController#create
const POLICY_URL = '/upload/policies/copilot-chat-attachments'

export interface DotcomFileAttachment extends FileAttachment {
  height?: number
  width?: number
  isLoaded: boolean
  hasError: boolean
}

export class UploadableFileAttachment implements DotcomFileAttachment {
  file: File
  width?: number
  height?: number
  #signal: AbortSignal
  key: string
  isLoaded = false
  hasError = false

  constructor(key: string, file: File, signal = new AbortController().signal) {
    this.file = file
    this.#signal = signal
    this.key = key
    this.getDimensions()
  }

  #resource = resource(async () => {
    const policy = await createPolicy(
      {
        name: this.file.name,
        size: String(this.file.size),
        // eslint-disable-next-line camelcase
        content_type: this.file.type,
      },
      POLICY_URL,
      this.#signal,
    )
    await uploadFile(this.file, policy, this.#signal)
    const asset = await complete(policy, this.#signal)
    this.isLoaded = true
    return asset
  })

  prefetch() {
    return this.#resource.load()
  }

  get previewUrl() {
    return this.#resource.read().href
  }

  async url() {
    const asset = await this.#resource.load()

    // TODO: This is all temporary, we really should be presigning just in time before calling the model
    // to ensure the url has enough time left in it.
    // GitHubModels::AttachmentsController#show
    const res = await verifiedFetch(asset.href)
    const attachment: {url: string} = await res.json()
    return attachment.url
  }

  private getDimensions() {
    const reader = new FileReader()
    reader.onload = loadedFileEvent => {
      // This executes asynchronously after the call to readAsDataURL.
      if (!loadedFileEvent.target || !loadedFileEvent.target.result) return
      const result = loadedFileEvent.target.result
      if (typeof result !== 'string') return

      const image = new Image()
      image.onload = () => {
        this.width = image.width
        this.height = image.height
      }
      image.src = result
    }
    reader.readAsDataURL(this.file)
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
            sendEvent('dotcom_chat.vision.error', {type: 'size_limit_exceeded', size: base64String.length})
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
            sendEvent('dotcom_chat.vision.error', {type: error.name, message: error.message})
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
}
