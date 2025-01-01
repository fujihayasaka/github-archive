import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {AssetSchema} from './asset'
import {LinkSchema} from './link'
import {PrimerComponentTimelineSchema} from './primerComponentTimeline'
import {PrimerComponentLabelSchema} from './primerComponentLabel'
import {AnimatedVideoSchema} from './animatedVideo'

export const PrimerComponentRiverSchema = buildEntrySchemaFor('primerComponentRiver', {
  fields: z.object({
    align: z.enum(['start', 'center', 'end']),
    imageTextRatio: z.enum(['50:50', '60:40']),
    label: PrimerComponentLabelSchema.optional(),
    heading: z.string(),
    headingLevel: z.enum(['h2', 'h3', 'h4', 'h5', 'h6']).optional(),
    text: RichTextSchema,
    trailingComponent: PrimerComponentTimelineSchema.optional(),
    callToAction: LinkSchema.optional(),
    callToActionVariant: z.enum(['default', 'accent']).optional(),
    image: AssetSchema.optional(),
    imageAlt: z.string().optional(),
    videoSrc: z.string().optional(),
    animatedVideo: AnimatedVideoSchema.optional(),
    hasShadow: z.boolean().optional(),
    htmlId: z.string().optional(),
  }),
})

export type PrimerComponentRiver = z.infer<typeof PrimerComponentRiverSchema>
