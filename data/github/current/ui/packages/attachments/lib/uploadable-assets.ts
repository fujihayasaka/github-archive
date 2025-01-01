/**
 * This module implements the uploadable assets flow. The process consists of three steps:
 *
 * 1. {@link createPolicy|Create a policy}.
 * 2. {@link uploadFile|Upload the file}.
 * 3. {@link complete|Complete the upload}.
 *
 * While similar to {@link app/assets/modules/github/upload/attachment-upload.ts|`AttachmentUpload`},
 * this implementation differs by using fetch instead of XHR and is not tied to the file-attachment-element,
 * as we implement a React-first upload flow.
 *
 * @module
 */

import {verifiedFetch} from '@github-ui/verified-fetch'

type AssetBase = {href: string; id: string}

export type UploadPolicy<Asset extends AssetBase = AssetBase> = {
  asset: Asset
  asset_upload_url: string

  // Fields for MemoryAlpha
  upload_url: string
  form: Record<string, string>
  header: Record<string, string>
  same_origin: boolean
}

/**
 * Creates a database entry and returns instructions for uploading the file through Memory Alpha.
 *
 * @param policyUrl You'd want to be calling UploadPoliciesController#create
 *
 * @returns A promise that resolves with the policy
 */
export async function createPolicy<
  T extends {
    name: string
    size: string
    content_type: string
  },
  Asset extends AssetBase = AssetBase,
>(policyRequest: T, policyUrl: string, signal: AbortSignal): Promise<UploadPolicy<Asset>> {
  const res = await verifiedFetch(
    policyUrl, // UploadPoliciesController#create
    {
      method: 'POST',
      body: formDataFromObject(policyRequest),
      signal,
    },
  )

  const json = await res.json()

  if (!res.ok) throw new GenericServerError('Error creating policy', json.errors)

  const policy = json as UploadPolicy<Asset>

  // Verify we can even complete this upload
  if (!policy.asset_upload_url) throw new Error('Unexpected error, missing asset upload URL')

  return policy
}

/**
 * Transfers the file to the relevant storage provider. A successful upload returns a 204 response.
 *
 * @param file The file to upload
 * @param policy The policy returned from {@link createPolicy}
 *
 * @returns A promise that resolves when the upload is complete
 */
export async function uploadFile(file: File, policy: UploadPolicy, signal: AbortSignal): Promise<void> {
  // NOTE: This won't be a "verifiedFetch", as we arent fetching dotcom.
  // This fetches out to MemoryAlpha, _or_ whatever the policy returns in `upload_url`.
  const res = await fetch(policy.upload_url, {
    method: 'POST',
    body: formDataFromObject({
      ...policy.form,
      file,
    }),
    signal,
  })

  // TODO: Confirm error types from MemoryAlpha
  if (!res.ok) throw new Error(await res.text())

  // The response is expected to be a 204 No Content. If it's anything else, we throw an error.
  // seeing a `Response.ok` as true, is enough to resolve this promise, and step as done.
}

/**
 * Marks the database entry as complete and returns the asset.
 *
 * @param policy The policy returned from {@link createPolicy}
 *
 * @returns A promise that resolves with the asset
 */
export async function complete<Asset extends AssetBase = AssetBase>(
  policy: UploadPolicy<Asset>,
  signal: AbortSignal,
): Promise<Asset> {
  const res = await verifiedFetch(
    policy.asset_upload_url, // UploadsController#update
    {
      method: 'PUT',
      signal,
    },
  )

  const json = await res.json()

  if (!res.ok) throw new GenericServerError('Error completing the upload', json.errors)

  return json
}

// ---

export class GenericServerError extends Error {
  errors: string[]

  constructor(message: string, errors: string[]) {
    super(message)
    this.name = 'GenericServerError'
    this.errors = errors
  }
}

function formDataFromObject(o: Record<string, string | Blob>): FormData {
  const formData = new FormData()
  for (const [key, value] of Object.entries(o)) {
    formData.append(key, value)
  }
  return formData
}
