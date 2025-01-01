import {z} from 'zod/v4'

/**
 * This schema verifies the payload received by the React application
 * has a known shape. The content inside "contentfulRawJsonResponse" should
 * be later validated by other schemas.
 */
export const PayloadSchema = z.object({
  contentfulRawJsonResponse: z.looseObject({}),
  userLoggedIn: z.boolean().optional(),
  additionalProps: z.object({page: z.number(), totalPages: z.number()}).optional(),
})

export type Payload = z.infer<typeof PayloadSchema>

export function toPayload(payload: unknown): Payload {
  return PayloadSchema.parse(payload)
}
