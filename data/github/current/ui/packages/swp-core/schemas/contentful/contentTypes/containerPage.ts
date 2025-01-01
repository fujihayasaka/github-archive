import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '../entry'
import {PageSettingsSchema} from './pageSettings'

export function buildPageSchemaForTemplate<Template extends z.ZodType>(templateSchema: Template) {
  return buildEntrySchemaFor('containerPage', {
    fields: z.object({
      path: z.string(),
      settings: PageSettingsSchema.optional(),
      template: templateSchema,
      title: z.string(),
    }),
  })
}
