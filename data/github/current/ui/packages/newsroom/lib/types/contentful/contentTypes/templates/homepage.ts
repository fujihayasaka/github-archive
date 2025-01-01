import {z} from 'zod'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {BackgroundImageSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/backgroundImage'
import {PrimerComponentSectionIntroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSectionIntro'
import {PrimerCardsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentStatisticSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStatistic'
import {AssetSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'

export const TemplateHomeSchema = buildEntrySchemaFor('newsroomTemplateHomepage', {
  fields: z.object({
    hero: PrimerComponentHeroSchema,
    heroBackgroundImage: BackgroundImageSchema,
    heroStatistics: z.array(PrimerComponentStatisticSchema).optional(),
    pressReleaseSectionIntro: PrimerComponentSectionIntroSchema,
    pressReleaseSectionCards: PrimerCardsSchema,
    reportsSectionIntro: PrimerComponentSectionIntroSchema,
    reportsSectionCards: PrimerCardsSchema,
    reportsStatisticsHeading: z.string().optional(),
    reportsSectionStatistics: z.array(PrimerComponentStatisticSchema).optional(),
    inTheNewsSectionIntro: PrimerComponentSectionIntroSchema,
    inTheNewsSectionCards: PrimerCardsSchema,
    customerStoriesSectionIntro: PrimerComponentSectionIntroSchema.optional(),
    featuredCustomerStories: PrimerCardsSchema.optional(),
    ctaSectionImage: AssetSchema.optional(),
    ctaSectionHeading: z.string().optional(),
    ctaSectionCards: PrimerCardsSchema.optional(),
    ctaBanner: PrimerComponentCtaBannerSchema,
    ctaBannerBackgroundImage: AssetSchema.optional(),
  }),
})

export type HomeTemplate = z.infer<typeof TemplateHomeSchema>
