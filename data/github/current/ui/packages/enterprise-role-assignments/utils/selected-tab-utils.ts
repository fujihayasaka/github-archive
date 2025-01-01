import type {SelectedTab} from '../types/selected-tab'
import {IS_KEY} from '../types/selected-tab'

export function updateSelectedTab(query: string, selectedTab: SelectedTab): string {
  // Remove any "is:*" tokens (i.e. "is:" followed by non-whitespace characters and an optional trailing space)
  const regex = new RegExp(`${IS_KEY}:\\S*\\s?`, 'g')
  const cleanedQuery = query.replace(regex, '').trim()
  // Prepend with the new selected tab
  return `${IS_KEY}:${selectedTab} ${cleanedQuery}`.trim()
}
