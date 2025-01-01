import type {ARIAFilterSuggestion} from '@github-ui/filter'
import {IterationsIcon} from '@primer/octicons-react'

export const getIterationMacros = (columnName: string): Array<ARIAFilterSuggestion> => {
  const columnNameLower = columnName.toLocaleLowerCase()
  return [
    {
      ariaLabel: '@current',
      value: '@current',
      priority: 2,
      displayName: `Current ${columnNameLower}`,
      inlineDescription: false,
      icon: IterationsIcon,
    },
    {
      ariaLabel: '@next',
      value: '@next',
      priority: 3,
      displayName: `Next ${columnNameLower}`,
      inlineDescription: false,
      icon: IterationsIcon,
    },
    {
      ariaLabel: '@previous',
      value: '@previous',
      priority: 4,
      displayName: `Previous ${columnNameLower}`,
      inlineDescription: false,
      icon: IterationsIcon,
    },
  ]
}
