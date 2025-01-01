import type {FilterProvider} from '@github-ui/filter'
import type {IssueTypeFilterProvider} from '@github-ui/issue-type-filter-provider'

export function isTypeFilterProvider(filterProvider: FilterProvider): filterProvider is IssueTypeFilterProvider {
  return (filterProvider as IssueTypeFilterProvider).displayName === 'Type'
}

export function isDirty(v: string | null | undefined): v is string {
  return v !== null && v !== undefined
}
