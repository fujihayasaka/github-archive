import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {AssetSchema} from './asset'
import {PrimerCardsSchema} from './primerCards'
import {PrimerPillarsSchema} from './primerPillars'
import {FeaturedBentoSchema} from './featuredBento'
import {IntroStackedItemsSchema} from './introStackedItems'
import {PrimerComponentLogoSuiteSchema} from './primerComponentLogoSuite'
import {PrimerComponentProseSchema} from './primerComponentProse'
import {PrimerComponentRiverSchema} from './primerComponentRiver'
import {PrimerComponentRiverBreakoutSchema} from './primerComponentRiverBreakout'
import {PrimerStatisticsSchema} from './primerStatistics'
import {PrimerComponentSectionIntroSchema} from './primerComponentSectionIntro'
import {PrimerComponentTestimonialSchema} from './primerComponentTestimonial'

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
    verticalGap: z.enum(['normal', 'spacious']).optional(),
    enableRiverStoryScroll: z.boolean().optional(),
    colorMode: z.enum(['light', 'dark', 'inherit']).optional(),
  }),
})

export const FlexSectionSchema = buildEntrySchemaFor('flexSection', {
  fields: z.object({
    id: z.string().optional(),
    introContent: z.union([IntroStackedItemsSchema, PrimerComponentSectionIntroSchema]).optional(),
    pillars: PrimerPillarsSchema.optional(),
    logoSuite: PrimerComponentLogoSuiteSchema.optional(),
    cards: PrimerCardsSchema.optional(),
    featuredBento: FeaturedBentoSchema.optional(),
    prose: PrimerComponentProseSchema.optional(),
    rivers: z.array(z.union([PrimerComponentRiverSchema, PrimerComponentRiverBreakoutSchema])).optional(),
    // In Contentful, we support a single-item list for Testimonials, but the array structure allows for
    // potential future support of multiple testimonials if needed.
    testimonials: z.array(PrimerComponentTestimonialSchema).optional(),
    statistics: PrimerStatisticsSchema.optional(),
    visualSettings: FlexSectionVisualSettingsSchema.optional(),
  }),
})

export type FlexSection = z.infer<typeof FlexSectionSchema>
