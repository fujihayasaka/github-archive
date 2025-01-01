import type {SharedBulkActionsItemPickerProps} from '@github-ui/item-picker/ItemPicker'

export type SharedListHeaderActionProps = {
  repo: string
  owner: string
  disabled: boolean
  singleKeyShortcutsEnabled: boolean
  /**
   * Whether to render the 'Add <property>' select panel as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
} & SharedBulkActionsItemPickerProps
