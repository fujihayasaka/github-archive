import {z} from 'zod/v4'
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

export const PrimerComponentPricingOptionsFeatureListGroupHeadingSchema = buildEntrySchemaFor(
  'primerComponentPricingOptionsListHeading',
  {
    fields: z.object({
      heading: RichTextSchema,
      headingLevel: z.enum(['h3', 'h4', 'h5', 'h6']).optional(),
    }),
  },
)
export type PrimerComponentPricingOptionsFeatureListGroupHeading = z.infer<
  typeof PrimerComponentPricingOptionsFeatureListGroupHeadingSchema
>

export const PrimerComponentPricingOptionsFeatureListHeadingSchema = buildEntrySchemaFor(
  'primerComponentPricingItemListHeading',
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
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    description: RichTextSchema.optional(),
    footnote: RichTextSchema.optional(),
    accordionHeadingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    featureList: z
      .array(
        z.union([
          PrimerComponentPricingOptionsFeatureListItemSchema,
          PrimerComponentPricingOptionsFeatureListGroupHeadingSchema,
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
    callToActionPrimaryVariant: z.enum(['accent', 'primary']).optional(),
    callToActionSecondary: LinkSchema.optional(),
    callToActionSecondaryVariant: z.enum(['subtle', 'secondary']).optional(),
  }),
})
export type PrimerComponentPricingOptionsItem = z.infer<typeof PrimerComponentPricingOptionsItemSchema>

export const PrimerComponentPricingOptionsSchema = buildEntrySchemaFor('primerComponentPricingOptions', {
  fields: z.object({
    align: z.enum(['start', 'center']).optional(),
    variant: z.enum(['default', 'cards', 'default-gradient', 'cards-gradient']).optional(),
    items: z.array(PrimerComponentPricingOptionsItemSchema),
  }),
})
export type PrimerComponentPricingOptions = z.infer<typeof PrimerComponentPricingOptionsSchema>
