import type {PlaygroundMessage} from '../../types'
import {
  getSavedPlaygroundMessages,
  clearPlaygroundLocalStorage,
  PlaygroundLocalStorage,
  setPlaygroundLocalStorageMessages,
} from '../playground-local-storage'

describe('Playground Local Storage', () => {
  beforeEach(() => {
    clearPlaygroundLocalStorage()
  })

  it('getSavedPlaygroundMessages returns null when no messages are saved', () => {
    const savedMessages = getSavedPlaygroundMessages()

    expect(savedMessages).toBeNull()
  })

  it('getSavedPlaygroundMessages returns saved messages', () => {
    const messages = {
      modelName: 'testModel',
      messages: [{message: 'Hello', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }
    setPlaygroundLocalStorageMessages(messages)

    const savedMessages = getSavedPlaygroundMessages()

    expect(savedMessages).toEqual(messages)
  })

  it('clearPlaygroundLocalStorage clears saved messages', () => {
    const messages = {
      modelName: 'testModel',
      messages: [{message: 'Hello', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }

    setPlaygroundLocalStorageMessages(messages)
    clearPlaygroundLocalStorage()
    const savedMessages = getSavedPlaygroundMessages()

    expect(savedMessages).toBeNull()
  })

  it('getter returns default values when no state is saved', () => {
    const storage = new PlaygroundLocalStorage()
    const defaultValues = {
      sidebarTab: 0,
      showSidebar: true,
      preferredLanguage: 'js',
      preferredSdk: '',
    }

    expect(storage.uiState).toEqual(defaultValues)
  })

  it('uiState getter/setter works', () => {
    const storage = new PlaygroundLocalStorage()
    const uiState = {
      sidebarTab: 1,
      showSidebar: false,
      preferredLanguage: 'ts',
      preferredSdk: 'sdk1',
    }
    storage.uiState = uiState

    expect(storage.uiState).toEqual(uiState)
  })
})
