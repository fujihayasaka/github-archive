import {AssetSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'
import {FeaturedBentoSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/featuredBento'
import {FormSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/form'
import {IntroPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introPillars'
import {IntroStackedItemsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introStackedItems'
import {PrimerCardsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'
import {PrimerComponentAnchorNavSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentAnchorNav'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentFaqSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaq'
import {PrimerComponentFaqGroupSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {PrimerComponentLogoSuiteSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLogoSuite'
import {PrimerComponentProseSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentProse'
import {PrimerComponentRiverSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiver'
import {PrimerComponentRiverBreakoutSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {PrimerComponentSectionIntroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSectionIntro'
import {PrimerComponentSubnavSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSubnav'
import {PrimerComponentTimelineSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTimeline'
import {PrimerPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerPillars'
import {PrimerStatisticsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerStatistics'
import {PrimerTestimonialsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerTestimonials'
import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {z} from 'zod'

export const TemplateFreeFormSectionSchema = buildEntrySchemaFor('templateFreeFormSection', {
  fields: z.object({
    id: z.string().optional(),
    components: z.array(
      z.union([
        PrimerComponentAnchorNavSchema,
        PrimerCardsSchema,
        PrimerComponentHeroSchema,
        PrimerComponentSectionIntroSchema,
        PrimerComponentRiverSchema,
        PrimerComponentRiverBreakoutSchema,
        PrimerComponentFaqGroupSchema,
        PrimerComponentFaqSchema,
        PrimerComponentCtaBannerSchema,
        PrimerPillarsSchema,
        PrimerComponentProseSchema,
        PrimerTestimonialsSchema,
        PrimerComponentTimelineSchema,
        PrimerComponentSubnavSchema,
        PrimerComponentLogoSuiteSchema,
        PrimerStatisticsSchema,
        FeaturedBentoSchema,
        FormSchema,
        IntroPillarsSchema,
        IntroStackedItemsSchema,
      ]),
    ),
    colorMode: z.enum(['inherit', 'light', 'dark']).default('inherit'),
    image: AssetSchema.optional(),
    imageMaxWidth: z.number().optional(),
  }),
})

export type TemplateFreeFormSection = z.infer<typeof TemplateFreeFormSectionSchema>
