import {afterEach, describe, it, assert} from '@github-ui/browser-tests'
import {cloneCurrentEventPayload, resetCurrentEventPayload, updateCurrentEventPayload} from '../tracking'

describe('tracking', () => {
  describe('updateCurrentEventPayload', () => {
    afterEach(() => {
      resetCurrentEventPayload()
    })

    it('starts with an empty event payload', () => {
      assert.deepEqual(cloneCurrentEventPayload(), {})
    })

    it('updates an existing fields on the current event payload', () => {
      const actual = {
        display_set: 'Team',
      }
      updateCurrentEventPayload(actual)
      assert.deepEqual(cloneCurrentEventPayload(), actual)

      const expected = {
        display_set: 'Project',
        query: 'team project',
      }
      updateCurrentEventPayload(expected)

      assert.deepEqual(cloneCurrentEventPayload(), expected)
    })
  })
})
