import type {DiffLine} from '@github-ui/diffs/types'

export type GroupedDiffs = {
  [category in DiffCategory]: DiffData[]
}

export type DiffData = {
  diffLines: DiffLine[]
  isBinary: boolean
  isTooBig: boolean
  linesAdded: number
  linesChanged: number
  linesDeleted: number
  newTreeEntry?: {mode: number; path: string}
  oldTreeEntry?: {mode: number; path: string}
  path: string
  risk?: number
  status: string
  truncatedReason?: string
}

export enum DiffCategory {
  Code = 'CODE',
  Tests = 'TESTS',
  Generated = 'GENERATED',
  Documentation = 'DOCUMENTATION',
  Data = 'DATA',
  Vendored = 'VENDORED',
  DependencyManagement = 'DEPENDENCY_MANAGEMENT',
  Binary = 'BINARY',
  Uncategorized = 'UNCATEGORIZED',
}

export const PATCH_RISK_THRESHOLD = 0.75

export const DIFF_CATEGORY_PRIORITY = {
  [DiffCategory.Code]: 1,
  [DiffCategory.Tests]: 2,
  [DiffCategory.Documentation]: 3,
  [DiffCategory.Data]: 4,
  [DiffCategory.Generated]: 5,
  [DiffCategory.Vendored]: 6,
  [DiffCategory.DependencyManagement]: 7,
  [DiffCategory.Binary]: 8,
  [DiffCategory.Uncategorized]: 9,
}

export function toSentenceCase(str: string) {
  const words = str.split('_')
  const titleCaseWord = (words[0]?.charAt(0) || '') + words[0]?.slice(1).toLowerCase()
  const lowerCaseWords = words.slice(1).map(word => word.toLowerCase())
  return [titleCaseWord, ...lowerCaseWords].join(' ')
}

export function compareDiffCategories(a: DiffCategory, b: DiffCategory) {
  return DIFF_CATEGORY_PRIORITY[a] - DIFF_CATEGORY_PRIORITY[b]
}
