import {
  isFileReference,
  makeCopilotChatReference,
  makeFolderReference,
  makeSymbolReference,
  referenceID,
} from './copilot-chat-helpers'
import type {CopilotChatManager} from './copilot-chat-manager'
import type {CopilotChatState} from './copilot-chat-reducer'
import type {
  CopilotChatReference,
  CopilotChatRepo,
  FileReference,
  FolderReference,
  SuggestionSymbolReference,
} from './copilot-chat-types'

export class CopilotAutocompleteManager {
  manager: CopilotChatManager
  fileSuggestions = new Map<string, FileReference>()
  folderSuggestions = new Map<string, FolderReference>()
  symbolSuggestions = new Map<string, SuggestionSymbolReference>()

  private repoSuggestionsCache = new Map<string, [Map<string, FileReference>, Map<string, FolderReference>]>()

  constructor(manager: CopilotChatManager) {
    this.manager = manager
  }

  async fetchAutocompleteSuggestions(repo: CopilotChatRepo, symbolQuery: string): Promise<void> {
    const [symbols, files] = await Promise.all([
      this.manager.service.querySymbols(repo, symbolQuery),
      this.manager.service.listRepoFiles(repo, true),
    ])

    if (symbols.ok) {
      const symbolResults = symbols.payload.flatMap(suggestion => {
        if (!suggestion.symbol) return []
        return [makeSymbolReference(suggestion, repo)]
      })
      this.symbolSuggestions = new Map(symbolResults.map($result => [$result.name, $result]))
    }

    if (this.repoSuggestionsCache.has(repo.name)) {
      ;[this.fileSuggestions, this.folderSuggestions] = this.repoSuggestionsCache.get(repo.name)!
      return
    }

    if (files.ok) {
      const filesByPath = new Map<string, FileReference>()
      const foldersByPath = new Map<string, FolderReference>()
      this.repoSuggestionsCache.set(repo.name, [filesByPath, foldersByPath])

      // Large repos could have hundreds of thousands of files, so we process them in chunks
      // to avoid blocking the main thread for too long.
      // This could eventually be done in a web worker too.
      const chunkSize = 5000
      let index = 0

      const items = [
        ...(files.payload.paths || []).map(path => ({type: 'path', path})),
        ...(files.payload.directories || []).map(path => ({type: 'folder', path})),
      ]

      const processChunk = () => {
        const end = Math.min(index + chunkSize, items.length)
        for (; index < end; index++) {
          const $item = items[index]
          if ($item?.type === 'path') {
            const ref = makeCopilotChatReference($item.path, repo)
            filesByPath.set(ref.path, ref)
          } else if ($item?.type === 'folder') {
            const ref = makeFolderReference($item.path, repo)
            foldersByPath.set(ref.path, ref)
          }
        }

        if (index < items.length) {
          setTimeout(processChunk, 0) // Schedule the next chunk
        } else {
          this.fileSuggestions = filesByPath
          this.folderSuggestions = foldersByPath
          return
        }
      }

      processChunk() // Start processing the first chunk
    }
  }

  /**
   * Adds a new reference to the list of references in the CopilotChatState.
   * If the reference already exists, it will not be added again.
   * @param newReference The new reference to be added.
   * @param state The current CopilotChatState.
   */
  async addToReferences(newReference: CopilotChatReference, state: CopilotChatState) {
    const uniqueID = referenceID(newReference)
    const existingReference = this.findReference(uniqueID, state)

    if (existingReference) return

    let referenceToAdd = newReference
    if (isFileReference(newReference)) {
      const response = await this.manager.service.fetchLanguageForFileReference(newReference)
      if (response.ok && response.payload.language) {
        const {languageName, languageId} = response.payload.language
        referenceToAdd = {...newReference, languageName, languageId}
      }
    }

    this.manager.addReference(referenceToAdd, 'autocomplete')
  }

  private findReference(uniqueID: string, state: CopilotChatState): CopilotChatReference | undefined {
    return state.currentReferences.find(value => uniqueID === referenceID(value))
  }
}
