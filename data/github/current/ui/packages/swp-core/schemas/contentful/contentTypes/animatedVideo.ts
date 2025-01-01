import {z} from 'zod/v4'
import {buildEntrySchemaFor} from '../entry'
import {AssetSchema} from './asset'

export const AnimatedVideoSchema = buildEntrySchemaFor('animatedVideo', {
  fields: z.object({
    video: AssetSchema,
    playLabel: z.string(),
    pauseLabel: z.string(),
    replayLabel: z.string(),
  }),
})

export type AnimatedVideo = z.infer<typeof AnimatedVideoSchema>
