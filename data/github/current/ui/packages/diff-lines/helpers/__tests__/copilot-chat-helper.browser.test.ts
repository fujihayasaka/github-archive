import {generateCopilotChatReference, isValidForCopilotChat, type CopilotChatDiffEntry} from '../copilot-chat-helper'
import {describe, it, expect} from '@github-ui/tests'

describe('copilot-chat-helper', () => {
  describe('isValidForCopilotChat', () => {
    const mockRepository = {
      id: 123,
      name: 'test-repo',
      ownerLogin: 'test-owner',
    }

    it('returns false when user has no Copilot access', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: false,
          isBinary: false,
          isSubmodule: false,
          path: 'test.ts',
          repository: mockRepository,
          status: 'MODIFIED',
        }),
      ).toBe(false)
    })

    it('returns false for binary files', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: true,
          isSubmodule: false,
          path: 'test.png',
          repository: mockRepository,
          status: 'MODIFIED',
        }),
      ).toBe(false)
    })

    it('returns false for submodules', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: false,
          isSubmodule: true,
          path: 'submodule',
          repository: mockRepository,
          status: 'MODIFIED',
        }),
      ).toBe(false)
    })

    it('returns false for deleted files', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: false,
          isSubmodule: false,
          path: 'deleted.ts',
          repository: mockRepository,
          status: 'DELETED',
        }),
      ).toBe(false)
    })

    it('returns false for files with no path', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: false,
          isSubmodule: false,
          path: '',
          repository: mockRepository,
          status: 'MODIFIED',
        }),
      ).toBe(false)
    })

    it('returns false for files with no repository data', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: false,
          isSubmodule: false,
          path: 'test.ts',
          repository: {
            id: 0,
            name: '',
            ownerLogin: '',
          },
          status: 'MODIFIED',
        }),
      ).toBe(false)
    })

    it('returns true for valid files', () => {
      expect(
        isValidForCopilotChat({
          hasCopilotAccess: true,
          isBinary: false,
          isSubmodule: false,
          path: 'valid.ts',
          repository: mockRepository,
          status: 'MODIFIED',
        }),
      ).toBe(true)
    })

    describe('generateCopilotChatReference', () => {
      const mockEntry: CopilotChatDiffEntry = {
        path: 'test.ts',
        pathDigest: 'abc123',
        newCommitOid: 'new-commit',
        oldCommitOid: 'old-commit',
        newTreeEntry: {
          path: 'test.ts',
          isGenerated: false,
          lineCount: undefined,
          mode: 0,
        },
        oldTreeEntry: {
          path: 'test.ts',
          lineCount: undefined,
          mode: 0,
        },
        repository: {
          id: 123,
          name: 'test-repo',
          ownerLogin: 'test-owner',
        },
        isBinary: false,
        isSubmodule: false,
        status: 'MODIFIED',
      }

      it('generates valid file diff reference', () => {
        const result = generateCopilotChatReference(mockEntry)

        expect(result).toEqual({
          baseFile: {
            type: 'file',
            path: 'test.ts',
            repoID: 123,
            repoName: 'test-repo',
            repoOwner: 'test-owner',
            ref: 'old-commit',
            commitOID: 'old-commit',
            url: '/test-owner/test-repo/raw/old-commit/test.ts',
          },
          headFile: {
            type: 'file',
            path: 'test.ts',
            repoID: 123,
            repoName: 'test-repo',
            repoOwner: 'test-owner',
            ref: 'new-commit',
            commitOID: 'new-commit',
            url: '/test-owner/test-repo/raw/new-commit/test.ts',
          },
          baseBranchRef: 'old-commit',
          id: '#diff-abc123',
          type: 'file-diff',
          url: '/test-owner/test-repo/raw/old-commit/test.ts',
        })
      })

      it('returns null file references when commit data is missing', () => {
        const result = generateCopilotChatReference({
          ...mockEntry,
          newCommitOid: undefined,
          oldCommitOid: undefined,
          newTreeEntry: null,
          oldTreeEntry: null,
        })

        expect(result.baseFile).toBeNull()
        expect(result.headFile).toBeNull()
        expect(result.url).toBe('')
      })
    })
  })
})
