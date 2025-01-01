import {z} from 'zod'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {FeaturedBentoSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/featuredBento'
import {IntroPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introPillars'
import {IntroStackedItemsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/introStackedItems'
import {PrimerCardsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'
import {PrimerComponentBreakoutBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentBreakoutBanner'
import {PrimerComponentCtaBannerSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'
import {PrimerComponentFaqGroupSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'
import {PrimerComponentFaqSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaq'
import {PrimerComponentLogoSuiteSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLogoSuite'
import {PrimerComponentPillarSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentPillar'
import {PrimerComponentProseSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentProse'
import {PrimerComponentRiverBreakoutSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {PrimerComponentRiverSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentRiver'
import {PrimerComponentTestimonialSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTestimonial'
import {PrimerComponentTimelineSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTimeline'
import {PrimerPillarsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerPillars'
import {PrimerStatisticsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerStatistics'
import {PrimerTestimonialsSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerTestimonials'

import {CopilotFeatureSchema} from './copilot-feature'
import {GenericAssetSchema} from './generic-asset'
import {GenericContentSchema} from './generic-content'

export const GenericGroupSchema = buildEntrySchemaFor('genericGroup', {
  fields: z.object({
    id: z.string().optional(),
    content: z
      .array(
        z.union([
          CopilotFeatureSchema,
          GenericAssetSchema,
          GenericContentSchema,
          FeaturedBentoSchema,
          IntroPillarsSchema,
          IntroStackedItemsSchema,
          PrimerCardsSchema,
          PrimerComponentBreakoutBannerSchema,
          PrimerComponentCtaBannerSchema,
          PrimerComponentFaqGroupSchema,
          PrimerComponentFaqSchema,
          PrimerComponentLogoSuiteSchema,
          PrimerComponentPillarSchema,
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
      .optional(),
  }),
})

export type GenericGroup = z.infer<typeof GenericGroupSchema>
