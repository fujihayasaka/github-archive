import {renderHook, waitFor} from '@testing-library/react'
import {setupUserEvent} from '@github-ui/react-core/test-utils'

import {useKeyPress, type OnKeyPressOptions} from '../use-key-press'

const scenarios: Array<{keysToListen: string[]; options: OnKeyPressOptions; userKeyPress: string; expected: number}> = [
  {keysToListen: ['B'], options: {ctrlKey: true}, userKeyPress: '{Control>}B{/Control}', expected: 1},
  {keysToListen: ['B'], options: {metaKey: true}, userKeyPress: '{Meta>}B{/Meta}', expected: 1},
  {keysToListen: ['/'], options: {}, userKeyPress: '[Slash]', expected: 1},
  {keysToListen: ['F6'], options: {metaKey: true}, userKeyPress: '{Meta>}{F6}{/Meta}', expected: 1},
  {
    keysToListen: ['B'],
    options: {shiftKey: true, ctrlKey: true},
    userKeyPress: '{Shift>}{Control>}B{/Control}{/Shift}',
    expected: 1,
  },
  {
    keysToListen: ['B'],
    options: {shiftKey: true},
    userKeyPress: '{Shift>}{Control>}B{/Control}{/Shift}',
    expected: 0,
  },
  {keysToListen: ['B'], options: {metaKey: true}, userKeyPress: '{Control>}B{/Control}', expected: 0},
  {keysToListen: ['A'], options: {metaKey: true}, userKeyPress: '{Meta>}B{/Meta}', expected: 0},
]

describe('useKeyPress', () => {
  test.each(scenarios)(
    'useKeyPress keysToListen: $keysToListen options: $options userKeyPress: $userKeyPress',
    async scenario => {
      const callback = jest.fn()
      const user = setupUserEvent()
      renderHook(() => useKeyPress(scenario.keysToListen, callback, scenario.options))

      await user.keyboard(scenario.userKeyPress)

      await waitFor(() => expect(callback).toHaveBeenCalledTimes(scenario.expected))
    },
  )
})
