import type {ZodType} from 'zod/v4'
import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {AssetSchema} from './asset'
import {PrimerCardsSchema, type PrimerCards} from './primerCards'
import {PrimerPillarsSchema, type PrimerPillars} from './primerPillars'
import {FeaturedBentoSchema, type FeaturedBentoType} from './featuredBento'
import {IntroStackedItemsSchema, type IntroStackedItems} from './introStackedItems'
import {PrimerComponentAnchorNavSchema, type PrimerComponentAnchorNav} from './primerComponentAnchorNav'
import {PrimerComponentLogoSuiteSchema, type PrimerComponentLogoSuite} from './primerComponentLogoSuite'
import {PrimerComponentProseSchema, type PrimerComponentProse} from './primerComponentProse'
import {PrimerComponentRiverSchema, type PrimerComponentRiver} from './primerComponentRiver'
import {PrimerComponentRiverBreakoutSchema, type PrimerComponentRiverBreakout} from './primerComponentRiverBreakout'
import {PrimerStatisticsSchema, type PrimerStatistics} from './primerStatistics'
import {PrimerComponentSectionIntroSchema, type PrimerComponentSectionIntro} from './primerComponentSectionIntro'
import {PrimerComponentTestimonialSchema, type PrimerComponentTestimonial} from './primerComponentTestimonial'
import {PrimerComponentBreakoutBannerSchema, type PrimerComponentBreakoutBanner} from './primerComponentBreakoutBanner'
import {PrimerComponentPricingOptionsSchema, type PrimerComponentPricingOptions} from './primerComponentPricingOptions'
import {SegmentedControlPanelSchema, type SegmentedControlPanel} from './segmentedControlPanel'
import {PrimerComponentRiverAccordionSchema, type PrimerComponentRiverAccordion} from './primerComponentRiverAccordion'

export const FlexSectionVisualSettingsSchema = buildEntrySchemaFor('flexSectionVisualSettings', {
  fields: z.object({
    paddingBlockStart: z.enum(['none', 'normal', 'condensed', 'spacious']).optional(),
    paddingBlockEnd: z.enum(['none', 'normal', 'condensed', 'spacious']).optional(),
    backgroundColor: z.enum(['default', 'subtle']).optional(),
    backgroundImage: AssetSchema.optional(),
    backgroundImagePosition: z
      .enum(['left', 'right', 'top left', 'top right', 'bottom left', 'bottom right', 'center', 'top', 'bottom'])
      .optional(),
    backgroundImageSize: z.enum(['cover', 'contain']).optional(),
    roundedCorners: z.boolean().optional(),
    verticalGap: z.enum(['normal', 'condensed', 'spacious']).optional(),
    enableRiverStoryScroll: z.boolean().optional(),
    colorMode: z.enum(['light', 'dark', 'inherit']).optional(),
    testimonialBackgroundImageVariant: z
      .enum(['Productivity', 'Collaboration', 'AI', 'Security', 'Enterprise'])
      .optional(),
    hasBorderBottom: z.boolean().optional(),
  }),
})

export type FlexSectionVisualSettings = z.infer<typeof FlexSectionVisualSettingsSchema>

/*
  Using FlexSection as a child type in segmentedControlPanel requires Zod's lazy loading.
  This prevents using z.infer<typeof FlexSectionSchema>, as it results in "any" types.
  To maintain type safety, we explicitly define the FlexSection type and declare FlexSectionSchema as ZodType<FlexSection>.
  Any changes to FlexSectionSchema must also update the FlexSection type.
*/
export type FlexSection = {
  sys: {
    id: string
    contentType: {
      sys: {
        id: 'flexSection'
      }
    }
  }
  fields: {
    id?: string
    introContent?: IntroStackedItems | PrimerComponentSectionIntro
    anchorNav?: PrimerComponentAnchorNav
    logoSuite?: PrimerComponentLogoSuite
    cards?: PrimerCards
    featuredBento?: FeaturedBentoType
    rivers?: Array<PrimerComponentRiver | PrimerComponentRiverBreakout | PrimerComponentRiverAccordion>
    testimonials?: PrimerComponentTestimonial[]
    breakoutBanner?: PrimerComponentBreakoutBanner
    statistics?: PrimerStatistics
    pricingOptions?: PrimerComponentPricingOptions
    segmentedControlPanel?: SegmentedControlPanel
    visualSettings?: FlexSectionVisualSettings
    prose?: PrimerComponentProse
    pillars?: PrimerPillars
  }
}

export const FlexSectionSchema: ZodType<FlexSection> = z.lazy(() =>
  buildEntrySchemaFor('flexSection', {
    fields: z.object({
      id: z.string().optional(),
      introContent: z.union([IntroStackedItemsSchema, PrimerComponentSectionIntroSchema]).optional(),
      anchorNav: PrimerComponentAnchorNavSchema.optional(),
      pillars: PrimerPillarsSchema.optional(),
      logoSuite: PrimerComponentLogoSuiteSchema.optional(),
      cards: PrimerCardsSchema.optional(),
      featuredBento: FeaturedBentoSchema.optional(),
      prose: PrimerComponentProseSchema.optional(),
      rivers: z
        .array(
          z.union([
            PrimerComponentRiverSchema,
            PrimerComponentRiverBreakoutSchema,
            PrimerComponentRiverAccordionSchema,
          ]),
        )
        .optional(),
      // In Contentful, we support a single-item list for Testimonials, but the array structure allows for
      // potential future support of multiple testimonials if needed.
      testimonials: z.array(PrimerComponentTestimonialSchema).optional(),
      breakoutBanner: PrimerComponentBreakoutBannerSchema.optional(),
      statistics: PrimerStatisticsSchema.optional(),
      pricingOptions: PrimerComponentPricingOptionsSchema.optional(),
      segmentedControlPanel: SegmentedControlPanelSchema.optional(),
      visualSettings: FlexSectionVisualSettingsSchema.optional(),
    }),
  }),
)
