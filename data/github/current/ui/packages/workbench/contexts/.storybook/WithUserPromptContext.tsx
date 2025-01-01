import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {UserPromptContext} from '../UserPromptContext'

export const withUserPromptContext: Decorator = (Story, {args}) => {
  const contextValue = {
    promptImage: undefined,
    setPromptImage: action('setPromptImage'),
    promptText: args.promptText as string,
    setPromptText: action('setPromptText'),
    promptError: args.promptError as string,
    setPromptError: action('setPromptError'),
    imageUploadError: args.imageUploadError as string,
    setImageUploadError: action('setImageUploadError'),
    attachImage: action('attachImage') as UserPromptContext['attachImage'],
    clearImageAttachment: action('clearImageAttachment'),
  } satisfies UserPromptContext

  return (
    <UserPromptContext.Provider value={contextValue}>
      <Story />
    </UserPromptContext.Provider>
  )
}

export const UserPromptContextDecoratorArgs = {
  promptText: 'a prompt',
  promptError: null,
  imageUploadError: undefined,
}

export const UserPromptContextDecoratorArgTypes = {
  promptText: {
    control: 'text',
    description: 'The text of the prompt',
    table: {
      category: 'UserPromptContext',
    },
  },
  promptError: {
    control: 'text',
    description: 'The error message for the prompt',
    table: {
      category: 'UserPromptContext',
    },
  },
  imageUploadError: {
    control: 'text',
    description: 'The error message for image upload',
    table: {
      category: 'UserPromptContext',
    },
  },
}
