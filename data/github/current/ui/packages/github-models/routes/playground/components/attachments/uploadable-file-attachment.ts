import {verifiedFetch} from '@github-ui/verified-fetch'
import {resource} from '@github-ui/attachments/util/resource'
import type {FileAttachment} from '@github-ui/attachments/types'
import {complete, createPolicy, uploadFile} from '@github-ui/attachments/uploadable'

// See: UploadPoliciesController#create
const POLICY_URL = '/upload/policies/models-attachments'

export class UploadableFileAttachment implements FileAttachment {
  file: File
  #signal: AbortSignal

  constructor(file: File, signal = new AbortController().signal) {
    this.file = file
    this.#signal = signal
  }

  // NOTE: We just use a random UUID, to give React something to key for. Useful if we put files in a loop, or to
  // indicate that a React component is the same, and thus its trees can be reused.
  key = globalThis.crypto.randomUUID()

  #resource = resource(async () => {
    const policy = await createPolicy(
      {
        name: this.file.name,
        size: String(this.file.size),
        content_type: this.file.type,
      },
      POLICY_URL,
      this.#signal,
    )
    await uploadFile(this.file, policy, this.#signal)
    return complete(policy, this.#signal)
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
    const attachment = await res.json()
    return attachment.url
  }
}
