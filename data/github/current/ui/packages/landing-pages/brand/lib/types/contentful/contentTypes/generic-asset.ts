import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '@github-ui/swp-core/schemas/contentful/entry'
import {AssetSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'

export const GenericAssetSchema = buildEntrySchemaFor('genericAsset', {
  fields: z.object({
    id: z.string().optional(),
    description: z.string().optional(),
    asset: AssetSchema,
    width: z.number().optional(),
    height: z.number().optional(),
  }),
})

export type GenericAsset = z.infer<typeof GenericAssetSchema>
