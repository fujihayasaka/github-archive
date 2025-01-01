import type {SuppliedFilterProvider} from '@github-ui/filter'

export interface IPickerItem {
  id: number
}

export interface SingleSelectProps<T extends IPickerItem> {
  /**
   * The selected item, or undefined if no item is selected.
   */
  selected?: T
  /**
   * - A callback function that is called when a item is selected and the dialog is closed.
   */
  onSubmit: (item: T | undefined) => void
}

export interface MultiSelectProps<T extends IPickerItem> {
  /**
   * The selected items or an empty array.
   */
  selected?: T[]
  /**
   * A callback function called every time selection changes in the dialog.
   * It's also called when the dialog is cancelled to reset to the original selection.
   */
  onChange?: (items: T[]) => void
  /**
   * A callback function that is called with the selection when the dialog is closed.
   */
  onSubmit: (items: T[]) => void
}

export interface DynamicProps {
  /**
   * Query string.
   */
  query?: string
  /**
   * A callback function that is called with the new query string when the dialog is closed.
   */
  onSubmit: (newQuery: string) => void
  /**
   * The list of filter providers to use in the filter component.
   */
  providers: SuppliedFilterProvider[]
  /**
   * If `true`, the dialog will show a warning if the query includes any provider not specified in `providers`.
   * It's ignored unless `providers` property is also set.
   * Defaults to `false`.
   */
  warnIfUnsupportedProvider?: boolean
}

export interface PublicDialogProps {
  onDismiss: () => void

  /**
   * Optional function to render custom UI on the dialog footer.
   */
  onRenderFooterDetails?(): React.ReactNode

  returnFocusRef?: React.RefObject<HTMLElement>
}

export interface InnerDialogProps<T extends IPickerItem> extends PublicDialogProps {
  itemConfig: ItemConfig<T>
  title: string
  description?: string
  providers: SuppliedFilterProvider[]
}

export interface ItemLiterals {
  itemName: string
  itemsName: string
  listTitle: string
}

export interface ItemConfig<T> extends ItemLiterals {
  getSearchUrl(query: string): string
  onRenderItemName(item: T): React.ReactNode
  onRenderItemLeadingVisual?(item: T): React.ReactNode
}
