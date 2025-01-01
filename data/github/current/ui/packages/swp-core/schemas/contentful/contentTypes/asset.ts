import {z} from 'zod/v4'

export const AssetSchema = z.object({
  fields: z.object({
    description: z.string().optional(),

    file: z.object({
      url: z.string(),
      details: z
        .object({
          image: z
            .object({
              width: z.number(),
              height: z.number(),
            })
            .optional(),
        })
        .optional(),
    }),
  }),
})

export type Asset = z.infer<typeof AssetSchema>
