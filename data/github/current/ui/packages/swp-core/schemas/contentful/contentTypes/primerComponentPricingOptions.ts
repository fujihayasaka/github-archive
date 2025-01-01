import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {PrimerComponentLabelSchema} from './primerComponentLabel'
import {LinkSchema} from './link'

export const PrimerComponentPricingOptionsFeatureListItemSchema = buildEntrySchemaFor(
  'primerComponentPricingOptionsListItem',
  {
    fields: z.object({
      variant: z.enum(['included', 'excluded']).optional(),
      description: RichTextSchema,
    }),
  },
)
export type PrimerComponentPricingOptionsFeatureListItem = z.infer<
  typeof PrimerComponentPricingOptionsFeatureListItemSchema
>

export const PrimerComponentPricingOptionsFeatureListHeadingSchema = buildEntrySchemaFor(
  'primerComponentPricingOptionsListHeading',
  {
    fields: z.object({
      heading: RichTextSchema,
    }),
  },
)
export type PrimerComponentPricingOptionsFeatureListHeading = z.infer<
  typeof PrimerComponentPricingOptionsFeatureListHeadingSchema
>

export const PrimerComponentPricingOptionsItemSchema = buildEntrySchemaFor('primerComponentPricingOptionsItem', {
  fields: z.object({
    heading: RichTextSchema,
    description: RichTextSchema.optional(),
    footnote: RichTextSchema.optional(),
    featureList: z
      .array(
        z.union([
          PrimerComponentPricingOptionsFeatureListItemSchema,
          PrimerComponentPricingOptionsFeatureListHeadingSchema,
        ]),
      )
      .optional(),
    featureListExpanded: z.boolean().optional(),
    featureListHasDivider: z.boolean().optional(),
    label: PrimerComponentLabelSchema.optional(),
    currentPrice: RichTextSchema,
    currencyCode: z.string().optional(),
    currencySymbol: z.string().optional(),
    originalPrice: z.string().optional(),
    priceTrailingText: z.string().optional(),
    callToActionPrimary: LinkSchema.optional(),
    callToActionSecondary: LinkSchema.optional(),
  }),
})
export type PrimerComponentPricingOptionsItem = z.infer<typeof PrimerComponentPricingOptionsItemSchema>

export const PrimerComponentPricingOptionsSchema = buildEntrySchemaFor('primerComponentPricingOptions', {
  fields: z.object({
    variant: z.enum(['default', 'cards']).optional(),
    items: z.array(PrimerComponentPricingOptionsItemSchema),
  }),
})
export type PrimerComponentPricingOptions = z.infer<typeof PrimerComponentPricingOptionsSchema>
