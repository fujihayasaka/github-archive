import safeStorage from '@github-ui/safe-storage'
import type {PlaygroundMessage} from '../../types'
import {
  getSavedPlaygroundMessages,
  clearPlaygroundLocalStorage,
  setPlaygroundLocalStorageMessages,
  getLocalStorageUiState,
  UI_STATE_KEY,
  setLocalStorageUiState,
  defaultUiState,
  getDefaultUiState,
  type ModelPersistentUIState,
} from '../playground-local-storage'
import {mockGettingStarted, mockLocalStorageUiState} from '../../routes/playground/__tests__/mocks'

const safeLocalStorage = safeStorage('localStorage')
afterEach(() => {
  safeLocalStorage.removeItem(UI_STATE_KEY)
})

describe('Playground Local Storage', () => {
  const marketplace = undefined
  const repository = {
    name: 'repo-name',
    ownerLogin: 'owner-login',
  }

  beforeEach(() => {
    clearPlaygroundLocalStorage(marketplace)
    clearPlaygroundLocalStorage(repository)
  })

  it('getSavedPlaygroundMessages returns null when no messages are saved', () => {
    const savedMessages = getSavedPlaygroundMessages(marketplace)

    expect(savedMessages).toBeNull()
  })

  it('getSavedPlaygroundMessages returns saved messages', () => {
    const marketplaceMessages = {
      modelName: 'testModel',
      messages: [{message: 'Hello from marketplace', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }

    const repoMessages = {
      modelName: 'testModel',
      messages: [{message: 'Hello from repo', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }

    setPlaygroundLocalStorageMessages(marketplaceMessages, marketplace)
    setPlaygroundLocalStorageMessages(repoMessages, repository)

    const savedMarketplaceMessages = getSavedPlaygroundMessages(marketplace)
    const savedRepoeMessages = getSavedPlaygroundMessages(repository)

    expect(savedMarketplaceMessages).toEqual(marketplaceMessages)
    expect(savedRepoeMessages).toEqual(repoMessages)
  })

  it('clearPlaygroundLocalStorage clears saved messages', () => {
    const marketplaceMessages = {
      modelName: 'testModel',
      messages: [{message: 'Hello from marketplace', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }

    const repoMessages = {
      modelName: 'testModel',
      messages: [{message: 'Hello from repo', timestamp: new Date(), role: 'user'} as PlaygroundMessage],
    }

    setPlaygroundLocalStorageMessages(marketplaceMessages, marketplace)
    setPlaygroundLocalStorageMessages(repoMessages, repository)

    clearPlaygroundLocalStorage(marketplace)
    clearPlaygroundLocalStorage(repository)

    const savedMarketplaceMessages = getSavedPlaygroundMessages(marketplace)
    const savedRepoeMessages = getSavedPlaygroundMessages(repository)

    expect(savedMarketplaceMessages).toBeNull()
    expect(savedRepoeMessages).toBeNull()
  })
})

describe('getLocalStorageUiState', () => {
  it('returns default values when no state is saved', () => {
    const uiState = getLocalStorageUiState()

    expect(uiState).toStrictEqual(defaultUiState)
  })

  it('returns default values when sidebarTab is saved as an invalid type', () => {
    const mockUiState = {...mockLocalStorageUiState, sidebarTab: '1234'}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const uiState = getLocalStorageUiState()

    expect(uiState).toEqual(defaultUiState)
  })

  it('returns default values when showSidebar is saved as an invalid type', () => {
    const mockUiState = {...mockLocalStorageUiState, showSidebar: '0'}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const uiState = getLocalStorageUiState()

    expect(uiState).toEqual(defaultUiState)
  })

  it('returns default values when preferredLanguage is saved as an invalid type', () => {
    const mockUiState = {...mockLocalStorageUiState, preferredLanguage: 0}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const uiState = getLocalStorageUiState()

    expect(uiState).toEqual(defaultUiState)
  })

  it('returns default values when preferredSdk is saved as an invalid type', () => {
    const mockUiState = {...mockLocalStorageUiState, preferredSdk: 0}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const uiState = getLocalStorageUiState()

    expect(uiState).toEqual(defaultUiState)
  })
})

describe('setLocalStorageUiState', () => {
  it('saves ui state in local storage', () => {
    const uiState: ModelPersistentUIState = {
      sidebarTab: 1,
      showSidebar: false,
      preferredLanguage: 'python',
      preferredSdk: 'sdk',
    }

    setLocalStorageUiState(uiState)
    const storedUiState = getLocalStorageUiState()

    expect(storedUiState).toEqual(uiState)
  })
})

describe('getDefaultUiState', () => {
  it('returns preferred language when it is provided as an arg and exists in the getting started', () => {
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted, 'python')
    expect(result.preferredLanguage).toEqual('python')
  })

  it('returns first available language when it does not exist in the getting started', () => {
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted, 'unknown')
    expect(result.preferredLanguage).toEqual('python')
  })

  it('returns language stored in the local storage when there is no preferred language argument provided', () => {
    const preferredLanguage = 'js'
    const mockUiState = {...mockLocalStorageUiState, preferredLanguage}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted)
    expect(result.preferredLanguage).toEqual(preferredLanguage)
  })

  it('returns the default language when there is no preferred language argument provided and no language stored in the local storage', () => {
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted)
    expect(result.preferredLanguage).toEqual('js')
  })

  it('returns default language if there is no language in the getting started', () => {
    const gettingStarted = {}
    const result = getDefaultUiState(gettingStarted)
    expect(result.preferredLanguage).toEqual('js')
  })

  it('returns preferred sdk when it is provided as an arg and exists in the getting started', () => {
    const gettingStarted = mockGettingStarted
    const preferredLanguage = 'python'
    const preferredSdk = 'azure-python-sdk-2'
    const result = getDefaultUiState(gettingStarted, preferredLanguage, preferredSdk)
    expect(result.preferredLanguage).toEqual(preferredLanguage)
    expect(result.preferredSdk).toEqual(preferredSdk)
  })

  it('returns first available sdk when it does not exist in the getting started', () => {
    const gettingStarted = mockGettingStarted
    const preferredLanguage = 'python'
    const result = getDefaultUiState(gettingStarted, preferredLanguage, 'unknown')
    expect(result.preferredLanguage).toEqual(preferredLanguage)
    expect(result.preferredSdk).toEqual('azure-python-sdk')
  })

  it('returns sdk stored in the local storage when there is no preferred language argument provided', () => {
    const preferredLanguage = 'js'
    const preferredSdk = 'azure-javascript-sdk-2'
    const mockUiState = {
      ...mockLocalStorageUiState,
      preferredLanguage,
      preferredSdk,
    }
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted)
    expect(result.preferredLanguage).toEqual(preferredLanguage)
    expect(result.preferredSdk).toEqual(preferredSdk)
  })

  it('returns first available sdk when there is no preferred sdk argument provided and no sdk stored in the local storage', () => {
    const gettingStarted = mockGettingStarted
    const result = getDefaultUiState(gettingStarted)
    expect(result.preferredLanguage).toEqual('js')
    expect(result.preferredSdk).toEqual('azure-javascript-sdk')
  })

  it('returns null if there is no sdk in the getting started', () => {
    const gettingStarted = mockGettingStarted
    const preferredLanguage = 'csharp'
    const result = getDefaultUiState(gettingStarted, preferredLanguage)
    expect(result.preferredLanguage).toEqual(preferredLanguage)
    expect(result.preferredSdk).toEqual('')
  })
})
