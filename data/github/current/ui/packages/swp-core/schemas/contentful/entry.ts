import {z} from 'zod/v4'

type ContentfulEntrySchema<ContentType extends z.core.util.Literal, Fields extends z.ZodType> = z.ZodObject<{
  sys: z.ZodObject<{
    id: z.ZodString

    contentType: z.ZodReadonly<
      z.ZodObject<{
        sys: z.ZodReadonly<
          z.ZodObject<{
            id: z.ZodReadonly<z.ZodLiteral<ContentType>>
          }>
        >
      }>
    >
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
export function buildEntrySchemaFor<ContentType extends z.core.util.Literal, Fields extends z.ZodType>(
  contentType: ContentType,
  options: {
    fields: Fields
  },
): ContentfulEntrySchema<ContentType, Fields> {
  return z.object({
    sys: z.object({
      id: z.string(),

      contentType: z
        .object({
          sys: z
            .object({
              id: z.literal(contentType).readonly(),
            })
            .readonly(),
        })
        .readonly(),
    }),
    fields: options.fields,
  })
}
