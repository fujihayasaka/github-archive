import {z} from 'zod/v4'

import {buildEntrySchemaFor} from '../entry'
import {FlexSectionSchema} from './flexSection'

export const SegmentedControlPanelItemSchema = buildEntrySchemaFor('segmentedControlPanelItem', {
  fields: z.object({
    label: z.string(),
    flexSections: z.array(z.lazy(() => FlexSectionSchema)),
  }),
})

export type SegmentedControlPanelItem = z.infer<typeof SegmentedControlPanelItemSchema>

export const SegmentedControlPanelSchema = buildEntrySchemaFor('segmentedControlPanel', {
  fields: z.object({
    ariaLabel: z.string().optional(),
    panelItems: z.array(SegmentedControlPanelItemSchema),
  }),
})

export type SegmentedControlPanel = z.infer<typeof SegmentedControlPanelSchema>
