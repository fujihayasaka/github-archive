import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {ContentFilterContext} from '../ContentFilterContext'

export const withContentFilter: Decorator = (Story, {args}) => {
  const contextValue = {
    filteredCategories: [],
    setFilteredCategories: action('setFilteredCategories'),
    isFilteredModalOpen: args.isFilteredModalOpen as boolean,
    setIsFilteredModalOpen: action('setIsFilteredModalOpen'),
    updateFilterExplanationContent: action('updateFilterExplanationContent'),
    clearFilterExplanationContent: action('clearFilterExplanationContent'),
    filterExplanationContent: args.filterExplanationContent as string,
  } satisfies ContentFilterContext

  return (
    <ContentFilterContext.Provider value={contextValue}>
      <Story />
    </ContentFilterContext.Provider>
  )
}

export const ContentFilterDecoratorArgs = {
  isFilteredModalOpen: false,
  filterExplanationContent: 'filter explanation',
}

export const ContentFilterDecoratorArgTypes = {
  setFilteredCategories: {table: {disable: true}},
  setIsFilteredModalOpen: {table: {disable: true}},
  updateFilterExplanationContent: {table: {disable: true}},
  clearFilterExplanationContent: {table: {disable: true}},
  isFilteredModalOpen: {
    control: 'boolean',
    table: {
      defaultValue: {summary: ContentFilterDecoratorArgs.isFilteredModalOpen.toString()},
      category: 'ContentFilterContext',
    },
  },
  filterExplanationContent: {
    control: 'text',
    table: {
      defaultValue: {summary: ContentFilterDecoratorArgs.filterExplanationContent},
      category: 'ContentFilterContext',
    },
  },
}
