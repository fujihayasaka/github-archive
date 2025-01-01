import {z} from 'zod'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {PrimerComponentSubnavSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSubnav'

import {GenericContentSchema} from './generic-content'
import {GenericSectionSchema} from './generic-section'

const BrandContentSchema = z.array(z.union([GenericContentSchema, GenericSectionSchema]))

export type BrandContentSchemaType = z.infer<typeof BrandContentSchema>

export const TemplateBrandSchema = buildEntrySchemaFor('templateBrand', {
  fields: z.object({
    subnav: PrimerComponentSubnavSchema.optional(),
    content: BrandContentSchema,
  }),
})

export type TemplateBrand = z.infer<typeof TemplateBrandSchema>
