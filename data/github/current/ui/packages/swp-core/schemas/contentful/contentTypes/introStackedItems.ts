import {z} from 'zod'
import {buildEntrySchemaFor} from '../entry'
import {IntroItemSchema} from './introItem'
import {LinkSchema} from './link'
import {RichTextSchema} from '../richText'

export const IntroStackedItemsSchema = buildEntrySchemaFor('introStackedItems', {
  fields: z.object({
    headline: z.union([z.string(), RichTextSchema]),
    items: z.array(IntroItemSchema),
    link: LinkSchema.optional(),
  }),
})

export type IntroStackedItems = z.infer<typeof IntroStackedItemsSchema>
