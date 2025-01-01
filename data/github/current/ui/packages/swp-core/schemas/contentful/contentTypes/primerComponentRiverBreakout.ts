import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {AssetSchema} from './asset'
import {LinkSchema} from './link'
import {PrimerComponentTimelineSchema} from './primerComponentTimeline'
import {AnimatedVideoSchema} from './animatedVideo'

export const PrimerComponentRiverBreakoutSchema = buildEntrySchemaFor('primerComponentRiverBreakout', {
  fields: z.object({
    a11yHeading: z.string(),
    headingLevel: z.enum(['h2', 'h3']).optional(),
    text: RichTextSchema,
    trailingComponent: PrimerComponentTimelineSchema.optional(),
    callToAction: LinkSchema.optional(),
    callToActionVariant: z.enum(['default', 'accent']).optional(),
    image: AssetSchema.optional(),
    imageAlt: z.string().optional(),
    animatedVideo: AnimatedVideoSchema.optional(),
    hasShadow: z.boolean().optional(),
    htmlId: z.string().optional(),
  }),
})

export type PrimerComponentRiverBreakout = z.infer<typeof PrimerComponentRiverBreakoutSchema>

export function isRiverBreakout(river: unknown): river is PrimerComponentRiverBreakout {
  return PrimerComponentRiverBreakoutSchema.safeParse(river).success
}
