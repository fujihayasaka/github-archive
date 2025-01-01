import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentStaticFootnotesSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStaticFootnotes'

export const TemplateCategorySchema = buildEntrySchemaFor('newsroomTemplateCategory', {
  fields: z.object({
    hero: PrimerComponentHeroSchema,
    ctaBanner: PrimerComponentCtaBannerSchema,
    staticFootnotes: PrimerComponentStaticFootnotesSchema.optional(),
  }),
})

export type CategoryTemplate = z.infer<typeof TemplateCategorySchema>
