import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {FeaturedBentoSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/featuredBento'
import {IntroPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introPillars'
import {IntroStackedItemsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introStackedItems'
import {PrimerCardsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'
import {PrimerComponentBreakoutBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentBreakoutBanner'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentFaqGroupSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'
import {PrimerComponentFaqSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaq'
import {PrimerComponentHeroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {PrimerComponentLogoSuiteSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLogoSuite'
import {PrimerComponentPillarSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentPillar'
import {PrimerComponentPricingOptionsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentPricingOptions'
import {PrimerComponentProseSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentProse'
import {PrimerComponentRiverBreakoutSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {PrimerComponentRiverSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiver'
import {PrimerComponentSectionIntroSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSectionIntro'
import {PrimerComponentTestimonialSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTestimonial'
import {PrimerComponentTimelineSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTimeline'
import {PrimerPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerPillars'
import {PrimerStatisticsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerStatistics'
import {PrimerTestimonialsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerTestimonials'

import {GenericContentSchema} from './generic-content'
import type {GenericContent} from './generic-content'

import {GenericGroupSchema} from './generic-group'
import type {GenericGroup} from './generic-group'

const GenericSectionContentSchema = z.array(
  z.union([
    GenericContentSchema,
    GenericGroupSchema,
    FeaturedBentoSchema,
    IntroPillarsSchema,
    IntroStackedItemsSchema,
    PrimerCardsSchema,
    PrimerComponentBreakoutBannerSchema,
    PrimerComponentCtaBannerSchema,
    PrimerComponentFaqGroupSchema,
    PrimerComponentFaqSchema,
    PrimerComponentHeroSchema,
    PrimerComponentLogoSuiteSchema,
    PrimerComponentPillarSchema,
    PrimerComponentPricingOptionsSchema,
    PrimerComponentProseSchema,
    PrimerComponentRiverBreakoutSchema,
    PrimerComponentRiverSchema,
    PrimerComponentTestimonialSchema,
    PrimerComponentTimelineSchema,
    PrimerPillarsSchema,
    PrimerStatisticsSchema,
    PrimerTestimonialsSchema,
  ]),
)

export type GenericSectionContentSchemaType = z.infer<typeof GenericSectionContentSchema>

export const GenericSectionSchema = buildEntrySchemaFor('genericSection', {
  fields: z.object({
    id: z.string().optional(),
    htmlId: z.string().optional(),
    sectionIntro: PrimerComponentSectionIntroSchema.optional(),
    content: GenericSectionContentSchema,
  }),
})

export type GenericSection = z.infer<typeof GenericSectionSchema>

export interface GenericSectionWithIds extends GenericSection {
  ids: {
    [key: string]: GenericContent | GenericGroup
  }
}
