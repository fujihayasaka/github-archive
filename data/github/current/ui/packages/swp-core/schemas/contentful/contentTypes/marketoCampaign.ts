import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '../entry'

export const MarketoCampaignSchema = buildEntrySchemaFor('marketoCampaign', {
  fields: z.object({
    cDLProgramName: z.string(),
    sFDCLastCampaignStatus: z.union([z.literal('Registered'), z.literal('Attended'), z.literal('Responded')]),
    source: z.string(),
    directToSfdcCampaignId: z.string().optional(),
    additionalProperties: z.looseObject({}).catchall(z.string()).optional(),
  }),
})

export type MarketoCampaign = z.infer<typeof MarketoCampaignSchema>
