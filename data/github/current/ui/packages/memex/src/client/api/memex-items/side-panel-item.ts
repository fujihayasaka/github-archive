import type {MemexItemModel} from '../../models/memex-item-model'
import type {SubIssueSidePanelItem} from './hierarchy'

// Represents an item that is viewable in the side panel.
// Includes both memex items, and sub-issues that do not belong to the project
export type SidePanelItem = MemexItemModel | SubIssueSidePanelItem

export const SidePanelTypeParam = {
  INFO: 'info',
  BULK_ADD: 'bulk-add',
  ISSUE: 'issue',
} as const
export type SidePanelTypeParam =
  | typeof SidePanelTypeParam.INFO
  | typeof SidePanelTypeParam.BULK_ADD
  | typeof SidePanelTypeParam.ISSUE
