import type {DynamicProps, MultiSelectProps, SingleSelectProps} from '@github-ui/filter-picker'

type RepositoryVisibility = 'public' | 'private' | 'internal'

export interface PickerRepository {
  id: number
  nodeId: string
  name: string
  ownerLogin: string
  visibility: RepositoryVisibility
}

type ValueType = 'string' | 'single_select' | 'multi_select' | 'true_false'

export interface PropertyDefinition {
  propertyName: string
  allowedValues?: string[]
  required?: boolean
  valueType: ValueType
}

export interface PickerScope {
  type: 'organization' | 'user' | 'enterprise'
  slug: string
  visibility?: RepositoryVisibility[]
}

export interface ReposPickerCommonProps extends Pick<React.HTMLAttributes<HTMLElement>, 'aria-describedby'> {
  /**
   * The scope to search repositories in. Either an organization or a user.
   */
  scope: PickerScope
  /**
   * Whether the dialog should be opened on first render.
   */
  isOpenInitially?: boolean
  /**
   * A function to change the default search endpoint.
   * Use it only if you need to add extra info on the result items.
   */
  getSearchUrl?(query: string): string
  /**
   * Optional function to render custom UI on the dialog footer.
   */
  onRenderFooterDetails?(): React.ReactNode
}

export type SingleSelectReposProps<TItem extends PickerRepository> = SingleSelectProps<TItem> & ReposPickerCommonProps

export type MultiSelectReposProps<TItem extends PickerRepository> = MultiSelectProps<TItem> & ReposPickerCommonProps

export type DynamicReposProps = DynamicProps & ReposPickerCommonProps
