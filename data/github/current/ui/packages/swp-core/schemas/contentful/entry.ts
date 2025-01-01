import {z} from 'zod'

type ContentfulEntrySchema<ContentType extends z.Primitive, Fields extends z.ZodTypeAny> = z.ZodObject<{
  sys: z.ZodObject<{
    id: z.ZodString

    contentType: z.ZodObject<{
      sys: z.ZodObject<{
        id: z.ZodLiteral<ContentType>
      }>
    }>
  }>

  fields: Fields
}>

/**
 * A function to build a zod schema for a Contentful entry.
 *
 * @param contentType The Contentful content type ID
 * @param options Additional options to build the schema
 * @param options.fields A zod schema representing the fields of the entry
 */
export function buildEntrySchemaFor<ContentType extends z.Primitive, Fields extends z.ZodTypeAny>(
  contentType: ContentType,
  options: {
    fields: Fields
  },
): ContentfulEntrySchema<ContentType, Fields> {
  return z.object({
    sys: z.object({
      id: z.string(),

      contentType: z.object({
        sys: z.object({
          id: z.literal(contentType),
        }),
      }),
    }),
    fields: options.fields,
  })
}
