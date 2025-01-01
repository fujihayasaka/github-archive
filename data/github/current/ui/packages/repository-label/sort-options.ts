import type {LabelOrderField} from './__generated__/LabelListQuery.graphql'

export const SORT_MAP: Record<'name' | 'count', Extract<LabelOrderField, 'NAME' | 'ISSUE_COUNT'>> = {
  name: 'NAME',
  count: 'ISSUE_COUNT',
} as const

export type SortKeyword = keyof typeof SORT_MAP
export const UI_SORT_VALUES = Object.keys(SORT_MAP) as readonly SortKeyword[]
export const VALID_UI_SORT_DIRECTIONS = ['asc', 'desc'] as const
