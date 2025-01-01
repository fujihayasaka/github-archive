import {z} from 'zod'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'

export const TemplateCategorySchema = buildEntrySchemaFor('newsroomTemplateCategory', {
  fields: z.object({
    hero: PrimerComponentHeroSchema,
    ctaBanner: PrimerComponentCtaBannerSchema,
  }),
})

export type CategoryTemplate = z.infer<typeof TemplateCategorySchema>
