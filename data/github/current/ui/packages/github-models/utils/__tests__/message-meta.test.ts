import {mockModel} from '../../routes/playground/__tests__/mocks'
import {mockStoredMessage, mockUser} from '../../routes/playground/components/__tests__/mocks'
import {determineMessageMeta} from '../message-meta'
import {TokenLimitReachedResponseErrorDescription} from '../playground-types'

describe('determineMessageMeta', () => {
  it("returns the model's name and image for an error message", () => {
    const message = Object.assign({}, mockStoredMessage, {
      message: TokenLimitReachedResponseErrorDescription,
      role: 'error',
    })
    const model = mockModel
    const currentUser = mockUser
    const expected = {name: mockModel.friendly_name, avatarUrl: mockModel.logo_url}
    expect(determineMessageMeta(message, model, currentUser)).toEqual(expected)
  })

  it("returns the model's name and image for an assistant message", () => {
    const message = Object.assign({}, mockStoredMessage, {
      message: 'test response',
      role: 'assistant',
    })
    const model = mockModel
    const currentUser = mockUser
    const expected = {name: mockModel.friendly_name, avatarUrl: mockModel.logo_url}
    expect(determineMessageMeta(message, model, currentUser)).toEqual(expected)
  })

  it("returns the user's name and image for a user's message", () => {
    const message = Object.assign({}, mockStoredMessage, {
      message: 'Hi',
      role: 'user',
    })
    const model = mockModel
    const currentUser = mockUser
    const expected = {name: currentUser.name, avatarUrl: currentUser.avatarUrl}
    expect(determineMessageMeta(message, model, currentUser)).toEqual(expected)
  })

  it("returns the name 'User' and github image for an unknown user's message", () => {
    const message = Object.assign({}, mockStoredMessage, {
      message: 'Hi',
      role: 'user',
    })
    const model = mockModel
    const currentUser = null
    const expected = {name: 'User', avatarUrl: '/github.png'}
    expect(determineMessageMeta(message, model, currentUser)).toEqual(expected)
  })

  it("returns the name 'default' and github image by default", () => {
    const message = Object.assign({}, mockStoredMessage, {
      message: 'Hi',
      role: 'mysterious role',
    })
    const model = mockModel
    const currentUser = null
    const expected = {name: 'default', avatarUrl: '/github.png'}
    expect(determineMessageMeta(message, model, currentUser)).toEqual(expected)
  })
})
