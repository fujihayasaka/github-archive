// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {getCommandSuggestions} from '../../components/task-oriented-assistive/commands'
import {
  getDocsetMock,
  getRepositoryMock,
  getRepositoryReferenceMock,
  getSnippetReferenceMock,
} from '../../test-utils/mock-data'
import {
  filterUniqueConfirmations,
  findAuthor,
  getThreadStaticSuggestions,
  referenceName,
  referencePath,
  referenceURL,
  validReferenceURL,
} from '../copilot-chat-helpers'
import type {
  CopilotChatMessage,
  CopilotChatReference,
  FileDiffReference,
  FileReference,
  GitHubAgentReference,
  RepoInstructionsReference,
  SnippetReference,
} from '../copilot-chat-types'
import {threadSuggestions} from '../prompts'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))
const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)

describe('#referenceName', () => {
  const baseFileDiff: FileDiffReference = {
    type: 'file-diff',
    id: 'some-id',
    url: 'fake-url',
    baseFile: {
      type: 'file',
      url: 'fake-url',
      path: '/some-file-name.ts',
      repoID: 1,
      repoOwner: 'my-owner',
      repoName: 'my-repo-name',
      ref: 'main',
      commitOID: '1234567',
    },
    headFile: {
      type: 'file',
      url: 'fake-url',
      path: '/some-file-name.ts',
      repoID: 1,
      repoOwner: 'my-owner',
      repoName: 'my-repo-name',
      ref: 'branch',
      commitOID: '2345678',
    },
  }
  const fileDiffStartOnly: FileDiffReference = {
    ...baseFileDiff,
    selectedRange: {
      start: 'L8',
    },
  }
  const fileDiffStartAndEndSame: FileDiffReference = {
    ...baseFileDiff,
    selectedRange: {
      start: 'L8',
      end: 'L8',
    },
  }
  const fileDiffStartAndEndDifferentLines: FileDiffReference = {
    ...baseFileDiff,
    selectedRange: {
      start: 'L1',
      end: 'L9',
    },
  }
  const fileDiffStartAndEndDifferentSides: FileDiffReference = {
    ...baseFileDiff,
    selectedRange: {
      start: 'L1',
      end: 'R1',
    },
  }
  it.each`
    description                                       | input                                | expected
    ${'File diff without selected ranges'}            | ${baseFileDiff}                      | ${'some-file-name.ts'}
    ${'File diff with start range only'}              | ${fileDiffStartOnly}                 | ${'some-file-name.ts L8'}
    ${'File diff with same start and end'}            | ${fileDiffStartAndEndSame}           | ${'some-file-name.ts L8'}
    ${'File diff with different start and end lines'} | ${fileDiffStartAndEndDifferentLines} | ${'some-file-name.ts L1-L9'}
    ${'File diff with different start and end sides'} | ${fileDiffStartAndEndDifferentSides} | ${'some-file-name.ts L1-R1'}
  `(
    'formats the name properly given a $description',
    ({input, expected}: {input: CopilotChatReference; expected: string}) => {
      expect(referenceName(input)).toEqual(expected)
    },
  )
})

describe('#referencePath', () => {
  test('returns the path of a file reference', () => {
    const ref: FileReference = {
      type: 'file',
      url: 'fake-url',
      path: 'some-file-name.ts',
      repoID: 1,
      repoOwner: 'my-owner',
      repoName: 'my-repo-name',
      ref: 'main',
      commitOID: '1234567',
    }
    const ref2: FileReference = {
      ...ref,
      path: 'foo/bar/baz.ts',
    }
    expect(referencePath(ref)).toEqual('/')
    expect(referencePath(ref2)).toEqual('foo/bar')
  })
})

describe('#referenceUrl', () => {
  const nonMarkdownSnippet: SnippetReference = {
    type: 'snippet',
    url: 'https://example.com/monalisa/smile/blob/master/README.md',
    path: 'README.md',
    repoID: 1,
    repoOwner: 'monalisa',
    repoName: 'smile',
    ref: '',
    commitOID: 'main',
    languageName: 'Ruby',
    range: {
      start: 1,
      end: 8,
    },
  }
  const markdownSnippet: SnippetReference = {
    ...nonMarkdownSnippet,
    languageName: 'Markdown',
  }

  test('returns the url of a non-markdown snippet', () => {
    const result = referenceURL(nonMarkdownSnippet)
    expect(result).toEqual(nonMarkdownSnippet.url)
    expect(result).not.toContain('plain=1')
  })

  test('returns the url of a repo-instruction reference', () => {
    const repoInstructionsReference: RepoInstructionsReference = {
      type: 'repo-instructions',
      url: 'https://example.com/monalisa/smile/blob/master/.github/copilot-instructions.md',
    }
    const result = referenceURL(repoInstructionsReference)
    expect(result).toEqual(repoInstructionsReference.url)
  })

  test('adds a `plain` parameter to markdown snippets', () => {
    const result = referenceURL(markdownSnippet)
    expect(result).toContain('plain=1')
    expect(result).toContain(markdownSnippet.url)
  })

  test('returns the display url of a third party reference', () => {
    const ref: CopilotChatReference = {
      type: 'third-party',
      displayName: 'Third party reference display name',
      displayIcon: 'https://example.com/example.png',
      displayUrl: 'https://example.com/example.html',
      data: '',
    }
    expect(referenceURL(ref)).toEqual(ref.displayUrl)
  })
})

describe('validReferenceURL', () => {
  it('should return true for a valid URL', () => {
    const url = 'https://example.com'
    const result = validReferenceURL(url)
    expect(result).toBe(true)
  })

  it('should return false for URL "#"', () => {
    const url = '#'
    const result = validReferenceURL(url)
    expect(result).toBe(false)
  })

  it('should return false for an empty URL', () => {
    const url = ''
    const result = validReferenceURL(url)
    expect(result).toBe(false)
  })
})

describe('#filterUniqueConfirmations', () => {
  test('returns an empty array when given an empty array', () => {
    expect(filterUniqueConfirmations([])).toEqual([])
  })

  test('returns an empty array when given null', () => {
    expect(filterUniqueConfirmations(null)).toEqual([])
  })

  test('returns one item when given an array with a single confirmation', () => {
    const confirmation = {
      title: 'some-title',
      message: 'some-message',
      confirmation: {},
    }
    expect(filterUniqueConfirmations([confirmation])).toEqual([confirmation])
  })

  test('returns one item when given an array with two identical confirmations', () => {
    const confirmation = {
      title: 'some-title',
      message: 'some-message',
      confirmation: {},
    }
    expect(filterUniqueConfirmations([confirmation, confirmation])).toEqual([confirmation])
  })

  test('returns an array with two confirmations when given an array with two different confirmations', () => {
    const confirmation1 = {
      title: 'some-title',
      message: 'some-message',
      confirmation: {arguments: {foo: 'bar'}},
    }
    const confirmation2 = {
      title: 'some-title',
      message: 'some-message',
      confirmation: {arguments: {foo: 'bar2'}},
    }
    expect(filterUniqueConfirmations([confirmation1, confirmation2])).toEqual([confirmation1, confirmation2])
  })
})

describe('getThreadStaticSuggestions', () => {
  beforeEach(() => {
    mockedIsFeatureEnabled.mockReturnValue(false)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('should default to repository type for non-references', () => {
    const resultTopic = getThreadStaticSuggestions(getRepositoryMock())
    expect(resultTopic.referenceType).toBe('repository')

    const resultDocset = getThreadStaticSuggestions(getDocsetMock())
    expect(resultDocset.referenceType).toBe('repository')
  })

  it('should handle v2 reference type variants', () => {
    const result = getThreadStaticSuggestions({
      type: 'file-v2',
      url: '',
      path: '',
      repoID: 0,
      repoOwner: '',
      repoName: '',
      ref: '',
      commitOID: '',
    })

    expect(result.referenceType).toBe('file-v2')
    const expected = threadSuggestions.file!
    const intersection = result.suggestions.filter(value => expected.includes(value))
    expect(result.suggestions.length).toEqual(3)
    expect(intersection.length).toEqual(result.suggestions.length)
  })

  it('should handle api reference type variants', () => {
    const result = getThreadStaticSuggestions({
      type: 'pull-request.api',
      number: 0,
    })

    expect(result.referenceType).toBe('pull-request.api')
    const expected = threadSuggestions['pull-request']!
    const intersection = result.suggestions.filter(value => expected.includes(value))
    expect(result.suggestions.length).toEqual(3)
    expect(intersection.length).toEqual(result.suggestions.length)
  })

  it('should return the default static suggestions', () => {
    const result = getThreadStaticSuggestions(getSnippetReferenceMock())

    const expected = threadSuggestions.default!
    const intersection = result.suggestions.filter(value => expected.includes(value))
    expect(result.suggestions.length).toEqual(3)
    expect(intersection.length).toEqual(result.suggestions.length)
  })

  describe('when task-oriented prompts feature is enabled', () => {
    beforeEach(() => {
      mockedIsFeatureEnabled.mockImplementation(
        (featureName: string) => featureName === 'copilot_task_oriented_assistive_prompts',
      )
    })

    describe('for pull request context', () => {
      it('should return the task-oriented commands', () => {
        const result = getThreadStaticSuggestions({
          type: 'pull-request',
          persona: 'author',
        } as unknown as CopilotChatReference)

        expect(result.suggestions.every(s => s.mode === 'task-oriented-assistive')).toBe(true)
        expect(result.suggestions.map(s => s.question)).toEqual(
          expect.arrayContaining([
            'Proof read this pull request',
            'Catch me up on the reviews',
            'Analyze build failures',
          ]),
        )
      })
    })

    describe('for repository context', () => {
      it('should return the task-oriented commands', () => {
        const result = getThreadStaticSuggestions(getRepositoryReferenceMock())

        expect(result.suggestions.every(s => s.mode === 'task-oriented-assistive')).toBe(true)
        expect(result.suggestions.map(s => s.question)).toEqual(
          // eslint-disable-next-line prettier/prettier
          expect.arrayContaining([
            'Tell me about this repository',
            'How to get started with this repository',
          ]),
        )
      })
    })

    describe('for global context', () => {
      it('should return the task-oriented commands', () => {
        const result = getThreadStaticSuggestions(getSnippetReferenceMock())

        const globalCommands = getCommandSuggestions('global')
        const expected = [...globalCommands, ...threadSuggestions.default!]

        expect(result.suggestions.length).toEqual(3)
        const test = result.suggestions.filter(value =>
          expected.some(expectedValue =>
            Object.keys(expectedValue).every(
              key => expectedValue[key as keyof typeof expectedValue] === value[key as keyof typeof value],
            ),
          ),
        )
        expect(test.length).toEqual(result.suggestions.length)

        const globalCommandsInResult = result.suggestions.filter(value =>
          globalCommands.some(expectedValue =>
            Object.keys(expectedValue).every(
              key => expectedValue[key as keyof typeof expectedValue] === value[key as keyof typeof value],
            ),
          ),
        )
        expect(globalCommandsInResult.every(s => s.mode === 'task-oriented-assistive')).toBe(true)
        expect(globalCommandsInResult.map(s => s.question)).toEqual(
          expect.arrayContaining(['Help me get started with Copilot']),
        )
      })
    })

    describe('when the reference type has no task-oriented prompts', () => {
      it('should use simple prompts', () => {
        const result = getThreadStaticSuggestions({
          type: 'job',
          id: '',
          repoId: 0,
          repoName: '',
          repoOwner: '',
        })

        const expected = threadSuggestions.job!
        const intersection = result.suggestions.filter(value => expected.includes(value))
        expect(intersection.length).toEqual(result.suggestions.length)
      })
    })
  })
})

describe('findAuthor', () => {
  const currentUserLogin = 'current-user'

  it('should return user author when message role is user', () => {
    const message: CopilotChatMessage = {
      role: 'user',
      id: '',
      createdAt: '',
      threadID: '',
      references: null,
    }
    const result = findAuthor(message, currentUserLogin)
    expect(result).toEqual({
      name: currentUserLogin,
      avatarURL: `/${currentUserLogin}.png`,
      type: 'user',
    })
  })

  it('should return agent author when message has agent reference', () => {
    const agentReference: GitHubAgentReference = {
      type: 'github.agent',
      login: 'agent-login',
      avatarURL: '/agent-login.png',
    }
    const message: CopilotChatMessage = {
      role: 'assistant',
      references: [agentReference],
      id: '',
      createdAt: '',
      threadID: '',
    }
    const result = findAuthor(message, currentUserLogin)
    expect(result).toEqual({
      name: agentReference.login,
      avatarURL: agentReference.avatarURL,
      type: 'agent',
    })
  })

  it('should return copilot author when no agent reference', () => {
    const message: CopilotChatMessage = {
      role: 'assistant',
      references: [],
      id: '',
      createdAt: '',
      threadID: '',
    }
    const result = findAuthor(message, currentUserLogin)
    expect(result).toEqual({
      name: 'Copilot',
      avatarURL: '',
      type: 'copilot',
    })
  })
})
