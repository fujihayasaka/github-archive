import type {SidePanelItem} from '../api/memex-items/side-panel-item'
import type {MemexItemModel} from '../models/memex-item-model'

/**
 * Shared return type for the sidepanel item hooks
 *
 * Used by both the legacy sidepanel item hook that shares query logic with the table,
 * and the new sidepanel item hook that is used with a separate dedicated query for the sidepanel item.
 *
 * Once the `memex_side_panel_query` feature flag is removed, this shared type can be removed as well.
 * This was moved into a separate file to prevent a circular dependency between the two sidepanel item hooks.
 *
 */

export type UseSidePanelItemReturnType = {
  paneItem: MemexItemModel | undefined
  isItemLoading: boolean
  reloadPaneItem: () => void
  setQueryDataForSidePanelItem: (item: SidePanelItem) => void
  setItemIsLoaded: (isLoaded: boolean) => void
  loadPaneItemData: (item: SidePanelItem) => void
}
