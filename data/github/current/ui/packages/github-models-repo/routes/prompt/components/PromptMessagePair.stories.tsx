import type {Meta, StoryObj} from '@storybook/react'
import type {MessagePair} from '../../../types'
import {messagePairLimit, PromptMessagePair} from './PromptMessagePair'

type StoryArgs = typeof PromptMessagePair

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models repository/PromptMessagePair',
  component: PromptMessagePair,
  args: {
    messagePairs: [],
    setMessagePairs: () => {},
    variableKeys: [],
  },
}

export default meta

type Story = StoryObj<StoryArgs>

export const Empty = {
  args: {
    messagePairs: [],
  },
} satisfies Story

export const SinglePair = {
  args: {
    messagePairs: [
      {
        assistant: 'I can help you with that! Here are some key points to consider...',
        user: 'Can you explain the main features of this system?',
      },
    ] as MessagePair[],
  },
} satisfies Story

export const MultiplePairs = {
  args: {
    messagePairs: [
      {
        assistant: 'GitHub Models is a platform for accessing AI models.',
        user: 'What is GitHub Models?',
      },
      {
        assistant: 'You can use it through the web interface or API calls.',
        user: 'How do I access it?',
      },
      {
        assistant: 'Yes, there are rate limits depending on your plan.',
        user: 'Are there any usage limits?',
      },
    ] as MessagePair[],
  },
} satisfies Story

export const WithVariables = {
  args: {
    messagePairs: [
      {
        assistant: 'Hello {{username}}! Welcome to {{platform}}.',
        user: 'Greet me using {{username}} and mention {{platform}}.',
      },
    ] as MessagePair[],
    variableKeys: ['username', 'platform', 'context'],
  },
} satisfies Story

export const EmptyPairs = {
  args: {
    messagePairs: [
      {assistant: '', user: ''},
      {assistant: '', user: ''},
    ] as MessagePair[],
  },
} satisfies Story

export const AtLimit = {
  args: {
    messagePairs: Array(messagePairLimit).fill({
      assistant: 'This is a sample assistant response.',
      user: 'This is a sample user question.',
    }) as MessagePair[],
  },
} satisfies Story

export const LongContent = {
  args: {
    messagePairs: [
      {
        assistant:
          'This is a very long assistant response that demonstrates how the component handles extensive text content. It includes multiple sentences and provides detailed information about the topic at hand. The response continues with more detailed explanations and examples to show how the text wraps and displays in the interface.',
        user: 'Please provide a detailed explanation with examples and make sure to include comprehensive information about the topic, including any relevant background context and practical applications.',
      },
    ] as MessagePair[],
  },
} satisfies Story
