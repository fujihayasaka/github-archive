import {setupUserEvent} from '@github-ui/react-core/test-utils'

import type {CommandId} from '../../commands'

const userEvent = setupUserEvent()

export const chordCommand = {
  id: 'ui-commands:test-chord',
  fire: async () => {
    await userEvent.keyboard('{Control>}{Shift>}{Enter}{/Shift}{/Control}')
  },
} as const
export const sequenceCommand = {
  id: 'ui-commands:test-sequence',
  fire: async () => {
    await userEvent.keyboard('g')
    await userEvent.keyboard('q')
  },
} as const
export const conflictingChordCommand = {
  id: 'ui-commands:conflicting-chord',
  fire: chordCommand.fire,
} as const
export const flaggedCommand = {
  id: 'ui-commands:flagged-command',
  fire: async () => {
    await userEvent.keyboard('a')
  },
} as const
export const singleKeyCommand = {
  id: 'ui-commands:single-key',
  fire: async () => {
    await userEvent.keyboard('a')
  },
} as const

export const mockHandler = () => jest.fn()
export const expectEventObject = ({id}: {id: CommandId}) => expect.objectContaining({commandId: id})
