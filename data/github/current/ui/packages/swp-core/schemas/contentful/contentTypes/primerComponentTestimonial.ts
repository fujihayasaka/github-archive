import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {RichTextSchema} from '../richText'
import {AssetSchema} from './asset'
import {PersonSchema} from './person'
import {TestimonialQuoteMarkColors} from '@primer/react-brand'

export const PrimerComponentTestimonialSchema = buildEntrySchemaFor('primerComponentTestimonial', {
  fields: z.object({
    quote: RichTextSchema,
    size: z.enum(['small', 'large']),
    variant: z.enum(['default', 'subtle', 'minimal', 'frosted-glass']).optional(),
    author: PersonSchema.optional(),
    displayedAuthorImage: z.enum(['none', 'avatar', 'logo']),
    logo: AssetSchema.optional(),
    quoteMarkColor: z.enum(TestimonialQuoteMarkColors).optional(),
  }),
})

export type PrimerComponentTestimonial = z.infer<typeof PrimerComponentTestimonialSchema>

export const isPrimerTestimonial = (entry: unknown): entry is PrimerComponentTestimonial => {
  return PrimerComponentTestimonialSchema.safeParse(entry).success
}
