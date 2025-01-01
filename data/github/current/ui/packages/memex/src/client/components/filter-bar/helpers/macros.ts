import type {ARIAFilterSuggestion} from '@github-ui/filter'
import {IterationsIcon, KeyAsteriskIcon} from '@primer/octicons-react'

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

export const getTextMacros = (columnName: string): Array<ARIAFilterSuggestion> => {
  const columnNameLower = columnName.toLocaleLowerCase()
  return [
    {
      ariaLabel: `term*, ${columnNameLower} starts with`,
      value: 'term*',
      priority: 2,
      displayName: `${columnNameLower} starts with...`,
      inlineDescription: false,
      icon: KeyAsteriskIcon,
    },
    {
      ariaLabel: `*term, ${columnNameLower} ends with`,
      value: '*term',
      priority: 3,
      displayName: `${columnNameLower} ends with...`,
      inlineDescription: false,
      icon: KeyAsteriskIcon,
    },
    {
      ariaLabel: `*term*, ${columnNameLower} contains`,
      value: '*term*',
      priority: 4,
      displayName: `${columnNameLower} contains...`,
      inlineDescription: false,
      icon: KeyAsteriskIcon,
    },
  ]
}
