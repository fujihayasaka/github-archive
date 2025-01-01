import {getReducerStateMock, getRepositoryMock} from '../../test-utils/mock-data'
import {CopilotAutocompleteManager} from '../copilot-autocompletions'
import type {CopilotChatManager} from '../copilot-chat-manager'
import type {CopilotChatService} from '../copilot-chat-service'
import type {FileReference} from '../copilot-chat-types'

describe('CopilotAutocompleteManager', () => {
  describe('fetchAutocompleteSuggestions', () => {
    it('returns empty suggestions if none exist', async () => {
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: {}}))
      chatService.querySymbols = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: []}))

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.service = chatService

      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const repo = getRepositoryMock()
      await autocomplete.fetchAutocompleteSuggestions(repo, '')

      expect(autocomplete.fileSuggestions.size).toEqual(0)
      expect(autocomplete.folderSuggestions.size).toEqual(0)
      expect(autocomplete.symbolSuggestions.size).toEqual(0)
    })

    it('returns empty suggestions if the service returns an error', async () => {
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: false, status: 500, error: "it's broke, yo"}))
      chatService.querySymbols = jest.fn(() => Promise.resolve({ok: false, status: 500, error: "it's broke, yo"}))

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.service = chatService

      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const repo = getRepositoryMock()
      await autocomplete.fetchAutocompleteSuggestions(repo, '')

      expect(autocomplete.fileSuggestions.size).toEqual(0)
      expect(autocomplete.folderSuggestions.size).toEqual(0)
      expect(autocomplete.symbolSuggestions.size).toEqual(0)
    })

    it('returns symbol suggestions', async () => {
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: {}}))
      chatService.querySymbols = jest.fn(() =>
        Promise.resolve({
          ok: true,
          status: 200,
          payload: [
            {
              kind: 'foo',
              query: 'foo',
              // eslint-disable-next-line camelcase
              repository_nwo: 'owner/repo',
              // eslint-disable-next-line camelcase
              language_id: 1,
              path: 'string',
              // eslint-disable-next-line camelcase
              repository_id: 1,
              // eslint-disable-next-line camelcase
              commit_sha: 'abc1234',
              // eslint-disable-next-line camelcase
              line_number: 1,
              symbol: {
                // eslint-disable-next-line camelcase
                fully_qualified_name: 'foo',
                kind: 'string',
                // eslint-disable-next-line camelcase
                ident_start: 1,
                // eslint-disable-next-line camelcase
                ident_end: 2,
                // eslint-disable-next-line camelcase
                extent_start: 3,
                // eslint-disable-next-line camelcase
                extent_end: 4,
              },
            },
            {
              kind: 'bar',
              query: 'bar',
              // eslint-disable-next-line camelcase
              repository_nwo: 'owner/repo',
              // eslint-disable-next-line camelcase
              language_id: 1,
              path: 'string',
              // eslint-disable-next-line camelcase
              repository_id: 1,
              // eslint-disable-next-line camelcase
              commit_sha: 'abc1234',
              // eslint-disable-next-line camelcase
              line_number: 1,
              symbol: null, // Results without a symbol are excluded
            },
          ],
        }),
      )

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.service = chatService

      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const repo = getRepositoryMock()
      await autocomplete.fetchAutocompleteSuggestions(repo, '')

      expect(autocomplete.symbolSuggestions.size).toEqual(1)
      expect(autocomplete.symbolSuggestions.has('foo')).toEqual(true)
    })

    it('returns file and folder suggestions', async () => {
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.listRepoFiles = jest.fn(() =>
        Promise.resolve({
          ok: true,
          status: 200,
          payload: {
            paths: ['src/index.ts', 'src/index.html', 'src/index.css', 'test/index.test.ts'],
            directories: ['src', 'test'],
          },
        }),
      )
      chatService.querySymbols = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: []}))

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.service = chatService

      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const repo = getRepositoryMock()
      await autocomplete.fetchAutocompleteSuggestions(repo, '')

      expect(autocomplete.fileSuggestions.size).toEqual(4)
      expect(autocomplete.fileSuggestions.has('src/index.ts')).toEqual(true)
      expect(autocomplete.fileSuggestions.has('src/index.html')).toEqual(true)
      expect(autocomplete.fileSuggestions.has('src/index.css')).toEqual(true)
      expect(autocomplete.fileSuggestions.has('test/index.test.ts')).toEqual(true)

      expect(autocomplete.folderSuggestions.size).toEqual(2)
      expect(autocomplete.folderSuggestions.has('src')).toEqual(true)
      expect(autocomplete.folderSuggestions.has('test')).toEqual(true)
    })

    it('caches file and folder results by repo', async () => {
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: {}}))
      chatService.querySymbols = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: []}))

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.service = chatService

      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const repo1 = getRepositoryMock()
      repo1.name = 'owner/repo-a'
      const repo1results = {
        paths: ['src/index.ts'],
        directories: ['src'],
      }

      const repo2 = getRepositoryMock()
      repo2.name = 'owner/repo-b'
      const repo2results = {
        paths: ['app/main.py'],
        directories: ['app'],
      }

      // Prime the cache with results from multiple repos
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: repo1results}))
      await autocomplete.fetchAutocompleteSuggestions(repo1, '')
      chatService.listRepoFiles = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: repo2results}))
      await autocomplete.fetchAutocompleteSuggestions(repo2, '')

      // Settle on the original repo
      await autocomplete.fetchAutocompleteSuggestions(repo1, '')

      // We should get results from repo1, for both files and folders
      expect(autocomplete.fileSuggestions.size).toEqual(1)
      expect(autocomplete.fileSuggestions.has('src/index.ts')).toEqual(true)
      expect(autocomplete.folderSuggestions.size).toEqual(1)
      expect(autocomplete.folderSuggestions.has('src')).toEqual(true)
    })
  })

  describe('addToReferences', () => {
    it('adds a file to the references', async () => {
      const addReferenceMock = jest.fn()
      const chatService = jest.createMockFromModule<CopilotChatService>('../copilot-chat-service')
      chatService.fetchLanguageForFileReference = jest.fn(() => Promise.resolve({ok: true, status: 200, payload: {}}))

      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      chatManager.addReference = addReferenceMock
      chatManager.service = chatService
      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const ref: FileReference = {
        type: 'file',
        url: '/primer/react/blob/main/packages/react/src/ActionList/index.ts',
        path: 'packages/react/src/ActionList/index.ts',
        repoID: 121814210,
        repoOwner: 'primer',
        repoName: 'react',
        ref: 'main',
        commitOID: '88ffc0d20eb26ddc93a97f2eb2f5ac19c257b1a2',
      }
      const state = getReducerStateMock()
      expect(state.currentReferences).toEqual([])

      await autocomplete.addToReferences(ref, state)

      expect(addReferenceMock).toHaveBeenCalledWith(ref, 'autocomplete')
    })

    it('skips adding a reference if it already exists', async () => {
      const chatManager = jest.createMockFromModule<CopilotChatManager>('../copilot-chat-manager')
      const addReferenceMock = jest.fn()
      chatManager.addReference = addReferenceMock
      const autocomplete = new CopilotAutocompleteManager(chatManager)

      const ref: FileReference = {
        type: 'file',
        url: '/primer/react/blob/main/packages/react/src/ActionList/index.ts',
        path: 'packages/react/src/ActionList/index.ts',
        repoID: 121814210,
        repoOwner: 'primer',
        repoName: 'react',
        ref: 'main',
        commitOID: '88ffc0d20eb26ddc93a97f2eb2f5ac19c257b1a2',
      }
      const state = getReducerStateMock()
      state.currentReferences = [ref]

      await autocomplete.addToReferences(ref, state)

      expect(addReferenceMock).not.toHaveBeenCalled()
    })
  })
})
