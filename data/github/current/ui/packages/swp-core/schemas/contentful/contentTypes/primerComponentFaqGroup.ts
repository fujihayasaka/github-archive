import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentFaqSchema} from './primerComponentFaq'
import {AccordionToggleColors} from '@primer/react-brand'

export const PrimerComponentFaqGroupSchema = buildEntrySchemaFor('primerComponentFaqGroup', {
  fields: z.object({
    heading: z.string(),
    faqs: z.array(PrimerComponentFaqSchema).optional(),
    htmlId: z.string().optional(),
    plusIconColor: z.enum(AccordionToggleColors).optional(),
  }),
})

export type PrimerComponentFaqGroup = z.infer<typeof PrimerComponentFaqGroupSchema>
