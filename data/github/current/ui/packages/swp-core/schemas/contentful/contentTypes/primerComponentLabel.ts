import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'

export const PrimerComponentLabelSchema = buildEntrySchemaFor('primerComponentLabel', {
  fields: z.object({
    text: z.string(),
    size: z.enum(['medium', 'large']),
    color: z.enum([
      'default',
      'blue',
      'coral',
      'green',
      'gray',
      'indigo',
      'lemon',
      'lime',
      'orange',
      'pink',
      'purple',
      'red',
      'teal',
      'yellow',
      'blue-purple',
      'green-blue',
      'pink-blue',
      'purple-red',
      'red-orange',
    ]),
    icon: z.string().optional(),
  }),
})

export type PrimerComponentLabel = z.infer<typeof PrimerComponentLabelSchema>
