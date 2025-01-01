import {cloneCurrentEventPayload, resetCurrentEventPayload, updateCurrentEventPayload} from '../tracking'
import {assert, suite, test} from '@github-ui/browser-tests'

suite('tracking', () => {
  suite('updateCurrentEventPayload', () => {
    teardown(() => {
      resetCurrentEventPayload()
    })

    test('starts with an empty event payload', () => {
      assert.deepEqual(cloneCurrentEventPayload(), {})
    })

    test('updates an existing fields on the current event payload', () => {
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
