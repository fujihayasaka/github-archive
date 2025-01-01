import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {PrimerComponentRiverAccordionItemSchema} from './primerComponentRiverAccordionItem'

export const PrimerComponentRiverAccordionSchema = buildEntrySchemaFor('primerComponentRiverAccordion', {
  fields: z.object({
    align: z.enum(['start', 'end']),
    riverAccordionItems: z.array(PrimerComponentRiverAccordionItemSchema),
    htmlId: z.string().optional(),
  }),
})

export type PrimerComponentRiverAccordion = z.infer<typeof PrimerComponentRiverAccordionSchema>

export function isRiverAccordion(river: unknown): river is PrimerComponentRiverAccordion {
  return PrimerComponentRiverAccordionSchema.safeParse(river).success
}
