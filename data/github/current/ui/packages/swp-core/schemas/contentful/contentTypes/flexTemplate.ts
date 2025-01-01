import {BackgroundImageSchema} from './backgroundImage'
import {PrimerComponentCtaBannerSchema} from './primerComponentCtaBanner'
import {PrimerComponentFaqGroupSchema} from './primerComponentFaqGroup'
import {PrimerComponentHeroSchema} from './primerComponentHero'
import {PrimerComponentSubnavSchema} from './primerComponentSubnav'
import {PrimerComponentSectionIntroSchema} from './primerComponentSectionIntro'
import {PrimerCardsSchema} from './primerCards'
import {FlexSectionSchema} from './flexSection'
import {buildEntrySchemaFor} from '../entry'
import {z} from 'zod'
import {buildPageSchemaForTemplate} from './containerPage'
import {PrimerComponentBreadcrumbSchema} from './primerComponentBreadcrumb'

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
    trailingSectionRoundedCorners: z.boolean().optional(),
    trailingSectionBackgroundColor: z.enum(['default', 'subtle']).optional(),
  }),
})

export const FlexPageSchema = buildPageSchemaForTemplate(TemplateFlexSchema)
export type FlexPage = z.infer<typeof FlexPageSchema>
