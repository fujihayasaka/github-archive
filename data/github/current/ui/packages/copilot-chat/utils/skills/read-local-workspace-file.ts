import safeStorage from '@github-ui/safe-storage'
import {BlobService} from '@github-ui/workspace-editor'
import {applyPatch, formatPatch, type ParsedDiff} from 'diff'

import type {ClientSideSkillDefinition} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'

type ReadLocalWorkspaceFileParams = {
  path: string
  repository: {ownerLogin: string; name: string}
  pullRequest: {number: string; headSHA: string}
}

export type BlobPayload = {
  blobContents?: string
  commitOid: string
  languageName?: string
  languageId?: string
  path: string
  refName: string
}

/*
 * The ReadLocalWorkspaceFileSkill is a client-side skill that allows Copilot to access the local contents
 * of a file in the Copilot Workspace for PRs (FKA Hadron) editor.
 *
 * Since uncommitted changes are stored in local storage as diff patches, this skill fetches the current blob
 * contents of the file via the API, and then attempts to save any locally saved patches to the blob to get the
 * full file contents.
 *
 * The result of these actions will be sent back to Copilot to finish answering the user's query.
 * In the case of an error, we return error as part of the result object, so that Copilot can interpret
 * the skill execution error as part of its final response the to user.
 *
 */
export class ReadLocalWorkspaceFileSkill implements ClientSkill {
  id: string
  name: string
  rawArguments: string
  blobService: BlobService

  constructor(id: string, name: string, rawArguments: string) {
    this.id = id
    this.name = name
    this.rawArguments = rawArguments
    this.blobService = new BlobService()
  }

  requiresConfirmation(): boolean {
    return false
  }

  confirmationMessage(): string {
    return 'Read the local workspace file'
  }

  static schema(): ClientSideSkillDefinition {
    return {
      type: 'function',
      function: {
        name: 'read-local-workspace-file',
        description:
          "Read a local file. This can be used to read files on the user's local machine. It is the equivalent of running `cat` in the terminal. The file path is relative to the current directory.",
        parameters: {
          type: 'object',
          required: ['path', 'repository', 'pullRequest'],
          properties: {
            path: {
              type: 'string',
              description: 'The path to the file to read.',
            },
            repository: {
              required: ['ownerLogin', 'name'],
              type: 'object',
              description: 'the repository containing the file to read.',
              properties: {
                ownerLogin: {
                  type: 'string',
                  description: 'the owner of the repository.',
                },
                name: {
                  type: 'string',
                  description: 'the name of the repository.',
                },
              },
            },
            pullRequest: {
              type: 'object',
              description: 'the pull request containing the file to read.',
              required: ['number', 'headSHA'],
              properties: {
                number: {
                  type: 'string',
                  description: 'the number of the pull request.',
                },
                headSHA: {
                  type: 'string',
                  description: 'the head SHA of the pull request.',
                },
              },
            },
          },
        },
      },
    }
  }

  private assertDefined<T>(object: T, error: string): asserts object is NonNullable<T> {
    if (object == null) {
      throw new Error(error)
    }
  }

  private validateArgs() {
    const parsedArgs = JSON.parse(this.rawArguments)
    this.assertDefined(parsedArgs, 'No parsed arguments found in raw arguments')
    this.assertDefined(parsedArgs.path, 'No path found on parsed arguments')
    this.assertDefined(parsedArgs.repository, 'No repository found on parsed arguments')
    this.assertDefined(parsedArgs.pullRequest, 'No pullRequest found on parsed arguments')
    this.assertDefined(parsedArgs.repository.ownerLogin, 'No ownerLogin found on repository')
    this.assertDefined(parsedArgs.repository.name, 'No name found on repository')
    this.assertDefined(parsedArgs.pullRequest.number, 'No number found on pullRequest')
    this.assertDefined(parsedArgs.pullRequest.headSHA, 'No headSHA found on pullRequest')

    return parsedArgs as ReadLocalWorkspaceFileParams
  }

  private getArguments() {
    const validParams = this.validateArgs()
    const {repository, pullRequest} = validParams
    const cleanedPath = validParams.path.startsWith('./') ? validParams.path.slice(2) : validParams.path

    return {path: cleanedPath, repository, pullRequest}
  }

  private async fetchBlob(
    path: string,
    repo: {ownerLogin: string; name: string},
    pull: {headSHA: string; number: string},
  ) {
    try {
      const response = await this.blobService.getBlob(path, repo.ownerLogin, pull.number, repo.name, pull.headSHA)
      return response.ok ? response.payload.blobContents || '' : ''
    } catch {
      return ''
    }
  }

  private toResult(result: string, ok: boolean) {
    return {ok, result}
  }

  async execute() {
    try {
      const safeLocalStorage = safeStorage('localStorage')
      const {path, repository, pullRequest} = this.getArguments()

      const blobContents = await this.fetchBlob(path, repository, pullRequest)

      const localStorageKey = `hadron-editor-file-deltas-v2/${repository.ownerLogin}/${repository.name}/${pullRequest.number}`
      const localStorageContent = JSON.parse(safeLocalStorage.getItem(localStorageKey) || '{}')
      const patches = (localStorageContent || {
        diffs: [],
        sessionId: '',
        latestTimestamp: 0,
      }) as {diffs?: Array<{path: string; diff: ParsedDiff}>}

      const patch = patches.diffs?.find(d => d.path === path)
      if (!patch) {
        return this.toResult(blobContents, true)
      }

      const patchResult = blobContents ? applyPatch(blobContents, patch.diff) : formatPatch(patch.diff)

      const result = patchResult === false ? blobContents : patchResult

      return this.toResult(result, true)
    } catch (e) {
      const error = `Error: ${e instanceof Error ? e.message : `Error executing ${this.name} skill`}`
      return this.toResult(error, false)
    }
  }
}
