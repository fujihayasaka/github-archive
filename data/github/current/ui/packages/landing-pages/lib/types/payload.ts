import {z} from 'zod/v4'

/**
 * This schema verifies the payload received by the React application
 * has a known shape. The content inside "contentfulRawJsonResponse" should
 * be later validated by other schemas.
 */
export const PayloadSchema = z.object({
  contentfulRawJsonResponse: z.looseObject({}).optional(),
  userLoggedIn: z.boolean().optional(),
  octocaptchaHost: z.string().optional(),
  copilotIdeDeepLinks: z.looseObject({}).optional(),
})

export type Payload = z.infer<typeof PayloadSchema>

export function toPayload(payload: unknown): Payload {
  return PayloadSchema.parse(payload)
}

export function isPayload(payload: unknown): payload is Payload {
  return PayloadSchema.safeParse(payload).success
}
