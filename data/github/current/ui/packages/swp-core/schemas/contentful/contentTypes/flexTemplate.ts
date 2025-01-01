import {z} from 'zod/v4'

import {BackgroundImageSchema} from './backgroundImage'
import {PrimerComponentCtaBannerSchema} from './primerComponentCtaBanner'
import {PrimerComponentFaqGroupSchema} from './primerComponentFaqGroup'
import {PrimerComponentHeroSchema} from './primerComponentHero'
import {PrimerComponentSubnavSchema} from './primerComponentSubnav'
import {PrimerComponentSectionIntroSchema} from './primerComponentSectionIntro'
import {PrimerCardsSchema} from './primerCards'
import {FlexSectionSchema} from './flexSection'
import {buildEntrySchemaFor} from '../entry'
import {buildPageSchemaForTemplate} from './containerPage'
import {PrimerComponentBreadcrumbSchema} from './primerComponentBreadcrumb'
import {PrimerComponentStaticFootnotesSchema} from './primerComponentStaticFootnotes'

export const FlexTemplateVisualSettingsSchema = buildEntrySchemaFor('flexTemplateVisualSettings', {
  fields: z.object({
    heroPaddingBlockEnd: z.enum(['none', 'condensed', 'spacious']).optional(),
    trailingSectionRoundedCorners: z.boolean().optional(),
    trailingSectionBackgroundColor: z.enum(['default', 'subtle']).optional(),
  }),
})

export const TemplateFlexSchema = buildEntrySchemaFor('templateFlex', {
  fields: z.object({
    subnav: PrimerComponentSubnavSchema.optional(),
    breadcrumbs: z.array(PrimerComponentBreadcrumbSchema).optional(),
    hero: PrimerComponentHeroSchema,
    heroBackgroundImage: BackgroundImageSchema.optional(),
    sections: z.array(FlexSectionSchema),
    ctaBanner: PrimerComponentCtaBannerSchema.optional(),
    sectionIntro: PrimerComponentSectionIntroSchema.optional(),
    cards: PrimerCardsSchema.optional(),
    faq: PrimerComponentFaqGroupSchema.optional(),
    staticFootnotes: PrimerComponentStaticFootnotesSchema.optional(),
    visualSettings: FlexTemplateVisualSettingsSchema.optional(),
  }),
})

export const FlexPageSchema = buildPageSchemaForTemplate(TemplateFlexSchema)
export type FlexPage = z.infer<typeof FlexPageSchema>
