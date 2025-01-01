import {isValidPlaygroundMessageJSON, validateJSONAsPlaygroundMessages} from '../playground-message-utils'
import {PlaygroundAPIMessageAuthorValues, type PlaygroundMessage} from '../../../../types'

describe('playground-message-utils', () => {
  describe('validateJSONAsPlaygroundMessages', () => {
    test('returns null for array with miscellaneous object JSON', () => {
      expect(validateJSONAsPlaygroundMessages('[{"foo": "bar"}]')).toBeNull()
    })

    test('returns null for invalid JSON', () => {
      expect(validateJSONAsPlaygroundMessages('{"foo": "bar]]]')).toBeNull()
    })

    for (const role of PlaygroundAPIMessageAuthorValues) {
      test(`returns message for valid JSON with role ${role}`, () => {
        const message: PlaygroundMessage = {role, message: 'Hello, world!', timestamp: new Date()}

        const result = validateJSONAsPlaygroundMessages(JSON.stringify([message]))

        expect(result).not.toBeNull()
        expect(result).toHaveLength(1)
        expect(result![0]).toEqual(message)
      })
    }

    test('returns multiple messages when every object is valid', () => {
      const message1: PlaygroundMessage = {role: 'user', message: 'Hello who is this', timestamp: new Date()}
      const message2: PlaygroundMessage = {role: 'system', message: 'yes this is dog', timestamp: new Date()}

      const result = validateJSONAsPlaygroundMessages(JSON.stringify([message1, message2]))

      expect(result).not.toBeNull()
      expect(result).toHaveLength(2)
      expect(result![0]).toEqual(message1)
      expect(result![1]).toEqual(message2)
    })

    test('returns null when one object is not a valid message', () => {
      const message: PlaygroundMessage = {role: 'user', message: 'The only message thingy', timestamp: new Date()}
      const someOtherObject = {foo: 'bar'}

      const result = validateJSONAsPlaygroundMessages(JSON.stringify([message, someOtherObject]))

      expect(result).toBeNull()
    })
  })

  describe('isValidPlaygroundMessageJSON', () => {
    test('returns true for valid JSON of list of messages', () => {
      const message1: PlaygroundMessage = {role: 'user', message: 'best bubbly water, go!', timestamp: new Date()}
      const message2: PlaygroundMessage = {role: 'system', message: 'Waterloo Peach obvs', timestamp: new Date()}
      const json = JSON.stringify([message1, message2])

      expect(isValidPlaygroundMessageJSON(json)).toBe(true)
    })

    test('returns false for invalid JSON', () => {
      expect(isValidPlaygroundMessageJSON('{"foo": "bar]]]')).toBe(false)
    })

    test('returns false for JSON that is not a list of messages', () => {
      expect(isValidPlaygroundMessageJSON('{"foo": "bar"}')).toBe(false)
    })

    test('returns false when one object is not a valid message', () => {
      const message: PlaygroundMessage = {role: 'user', message: 'The only message thingy', timestamp: new Date()}
      const someOtherObject = {foo: 'bar'}
      const json = JSON.stringify([message, someOtherObject])

      expect(isValidPlaygroundMessageJSON(json)).toBe(false)
    })
  })
})
