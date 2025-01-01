import {z} from 'zod'

import {buildEntrySchemaFor} from '../entry'

export const MarketoCampaignSchema = buildEntrySchemaFor('marketoCampaign', {
  fields: z.object({
    cDLProgramName: z.string(),
    sFDCLastCampaignStatus: z.union([z.literal('Registered'), z.literal('Attended'), z.literal('Responded')]),
    source: z.string(),
    extraFormAttributes: z.record(z.string()).optional(),
  }),
})

export type MarketoCampaign = z.infer<typeof MarketoCampaignSchema>
