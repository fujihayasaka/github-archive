import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {AccordionToggleColors} from '@primer/react-brand'

const PrimerComponentFaqQuestionSchema = buildEntrySchemaFor('primerComponentFaqQuestion', {
  fields: z.object({
    question: z.string(),
    answer: RichTextSchema,
  }),
})

const PrimerComponentFaqBlockSchema = buildEntrySchemaFor('primerComponentFaqBlock', {
  fields: z.object({
    plusIconColor: z.enum(AccordionToggleColors).optional(),
    heading: z.string().optional(),
    questions: z.array(PrimerComponentFaqQuestionSchema).optional(),
  }),
})

export const PrimerComponentFaqSchema = buildEntrySchemaFor('primerComponentFaq', {
  fields: z.object({
    heading: z.string(),
    blocks: z.array(PrimerComponentFaqBlockSchema).optional(),
  }),
})

export type PrimerComponentFaq = z.infer<typeof PrimerComponentFaqSchema>
