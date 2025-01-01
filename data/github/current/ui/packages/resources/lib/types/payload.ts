import {z} from 'zod/v4'

/**
 * This schema verifies the payload received by the React application
 * has a known shape. The content inside "contentfulRawJsonResponse" should
 * be later validated by other schemas.
 */
export const PayloadSchema = z.object({
  contentfulRawJsonResponse: z.looseObject({}),
  userLoggedIn: z.boolean().optional(),
})

export const CategoryPayloadSchema = PayloadSchema.extend({
  additionalProps: z.object({
    pageHeading: z.string(),
    page: z.number(),
    totalPages: z.number(),
  }),
})

const WhitepaperContentTypes = z.enum(['whitepaper', 'ebook'])
const WhitepaperCategories = z.enum([
  'ai',
  'cloud',
  'devops',
  'github-actions',
  'github-advanced-security',
  'github-enterprise',
  'innersource',
  'open-source',
  'security',
  'software-development',
])

export const WhitepaperIndexPayloadSchema = PayloadSchema.extend({
  additionalProps: z.object({
    page: z.number(),
    totalPages: z.number(),
    filters: z.object({
      contentTypes: z.array(WhitepaperContentTypes).optional(),
      topics: z.array(WhitepaperCategories).optional(),
    }),
  }),
})

export type Payload = z.infer<typeof PayloadSchema>
export type CategoryPayload = z.infer<typeof CategoryPayloadSchema>
export type WhitepaperIndexPayload = z.infer<typeof WhitepaperIndexPayloadSchema>

export function toPayload(payload: unknown): Payload {
  return PayloadSchema.parse(payload)
}

export function toCategoryPayload(payload: unknown): CategoryPayload {
  return CategoryPayloadSchema.parse(payload)
}

export function toWhitepaperIndexPayload(payload: unknown): WhitepaperIndexPayload {
  return WhitepaperIndexPayloadSchema.parse(payload)
}
