import {z} from 'zod'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {RichTextSchema} from '@github-ui/swp-core/schemas/contentful/richText'
import {PrimerComponentLabelSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLabel'

const COPILOT_FEATURE_STATUS = z.enum(['Disabled', 'Enabled', 'Refresh', 'Unlimited'])

export const CopilotFeatureSchema = buildEntrySchemaFor('copilotFeature', {
  fields: z.object({
    label: PrimerComponentLabelSchema.optional(),
    heading: RichTextSchema,
    subheading: RichTextSchema.optional(),
    statusForFree: COPILOT_FEATURE_STATUS,
    statusForPro: COPILOT_FEATURE_STATUS,
    statusForProPlus: COPILOT_FEATURE_STATUS,
    statusForBusiness: COPILOT_FEATURE_STATUS,
    statusForEnterprise: COPILOT_FEATURE_STATUS,
    customTextForFree: RichTextSchema.optional(),
    customTextForPro: RichTextSchema.optional(),
    customTextForProPlus: RichTextSchema.optional(),
    customTextForBusiness: RichTextSchema.optional(),
    customTextForEnterprise: RichTextSchema.optional(),
  }),
})

export type CopilotFeature = z.infer<typeof CopilotFeatureSchema>
