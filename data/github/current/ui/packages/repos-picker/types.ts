import type {ReposFilter} from '@github-ui/repos-filter'

type RepositoryVisibility = 'public' | 'private' | 'internal'

export interface PickerRepository {
  id: number
  nodeId: string
  name: string
  ownerLogin: string
  visibility: RepositoryVisibility
}

type ValueType = 'string' | 'single_select' | 'multi_select' | 'true_false'

export interface FetchRepositoriesData {
  repositories: PickerRepository[]
  repositoryCount: number
}

export interface PropertyDefinition {
  propertyName: string
  allowedValues?: string[]
  required?: boolean
  valueType: ValueType
}

export interface ReposPickerCommonProps {
  /**
   * - If `orgLogin` is set, the repository list is scoped to the organization,
   *   and the search filter is enriched with the organization's custom properties.
   * - If `orgLogin` is not set, all public repositories are listed,
   *   and no custom properties are available to the search filter.
   */
  orgLogin?: string
}

export interface SingleSelectProps extends ReposPickerCommonProps {
  /**
   * The selected repository, or undefined if no repository is selected.
   */
  selected?: PickerRepository
  /**
   * - A callback function that is called when a repository is selected and the dialog is closed.
   */
  onSubmit: (item: PickerRepository | undefined) => void
}

export interface MultiSelectProps extends ReposPickerCommonProps {
  /**
   * The selected repositories or an empty array.
   */
  selected?: PickerRepository[]
  /**
   * A callback function that is called with the selection when the dialog is closed.
   */
  onSubmit: (items: PickerRepository[]) => void
}

export interface DynamicMatchingProps extends ReposPickerCommonProps {
  /**
   * Query string.
   */
  query?: string
  /**
   * A callback function that is called with the new query string when the dialog is closed.
   */
  onSubmit: (newQuery: string) => void

  /**
   * Allowed provider keys for the repository filter component.
   * Custom properties provider is a special case and is described with a key `custom-properties`.
   */
  allowedProviders?: React.ComponentProps<typeof ReposFilter>['allowedProviders']
}

export interface CommonDialogProps {
  onDismiss: () => void
  returnFocusRef?: React.RefObject<HTMLElement>
}
