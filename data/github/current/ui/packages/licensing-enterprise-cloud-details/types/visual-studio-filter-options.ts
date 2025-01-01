export const VisualStudioFilter = {
  All: 'all',
  AutomaticallyMatched: 'automatically-matched',
  ManuallyMatched: 'manually-matched',
  Unmatched: 'unmatched',
} as const

export type VisualStudioFilter = (typeof VisualStudioFilter)[keyof typeof VisualStudioFilter]

export const visualStudioFilterOptions: Array<{value: VisualStudioFilter; name: string}> = [
  {value: VisualStudioFilter.All, name: 'All'},
  {value: VisualStudioFilter.AutomaticallyMatched, name: 'Automatically matched'},
  {value: VisualStudioFilter.ManuallyMatched, name: 'Manually matched'},
  {value: VisualStudioFilter.Unmatched, name: 'Unmatched'},
]
