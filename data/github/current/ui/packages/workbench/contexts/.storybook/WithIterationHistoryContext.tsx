import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import type {Iteration} from '../../types/workbench-types'

import {IterationHistoryContext} from '../IterationHistoryContext'

export const withIterationHistoryContext: Decorator = (Story, {args}) => {
  const contextValue = {
    setCurrentRefinement: action('setCurrentRefinement'),
    previousRefinements: [{
      iteration_type: 'ai',
      prompt: "User's prompt",
      sha: "abc123",
      files: {},
      id: 1,
      parentId: null,
      suggestions: ["Suggestion 1", "Suggestion 2"],
      error: {message: "Error message"}
    } satisfies Iteration],
    setPreviousRefinements: action('setPreviousRefinements'),
    currentRefinementId: args.currentRefinementId,
    isNavigatingHistory: args.isNavigatingHistory,
    setIsNavigatingHistory: action('setIsNavigatingHistory'),
  } as IterationHistoryContext

  return (
    <IterationHistoryContext.Provider value={contextValue}>
      <Story />
    </IterationHistoryContext.Provider>
  )
}

export const IterationHistoryContextDecoratorArgTypes = {
  currentRefinementId: {
    control: 'number',
    description: 'The current refinement ID',
    table: {
      category: 'IterationHistoryContext',
    },
  },
  isNavigatingHistory: {
    control: 'boolean',
    description: 'Whether the user is currently navigating history',
    table: {
      category: 'IterationHistoryContext',
    },
  },
}

export const IterationHistoryContextDecoratorArgs = {
  currentRefinementId: 1,
  isNavigatingHistory: false,
}
