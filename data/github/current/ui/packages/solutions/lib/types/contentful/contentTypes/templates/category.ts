import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {PrimerComponentBreakoutBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentBreakoutBanner'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentStatisticSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStatistic'
import {PrimerCardsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'
import {PrimerComponentStaticFootnotesSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStaticFootnotes'

export const TemplateCategorySchema = buildEntrySchemaFor('solutionsTemplateCategory', {
  fields: z.object({
    hero: PrimerComponentHeroSchema,
    solutionPageCards: PrimerCardsSchema,
    relatedSolutionCards: PrimerCardsSchema.optional(),
    breakoutBanner: PrimerComponentBreakoutBannerSchema.optional(),
    featuredStatistics: z.array(PrimerComponentStatisticSchema).optional(),
    ctaBanner: PrimerComponentCtaBannerSchema,
    staticFootnotes: PrimerComponentStaticFootnotesSchema.optional(),
  }),
})

export type CategoryTemplate = z.infer<typeof TemplateCategorySchema>
