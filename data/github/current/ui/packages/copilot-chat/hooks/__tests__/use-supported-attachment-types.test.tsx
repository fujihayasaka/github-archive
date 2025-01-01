// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@github-ui/react-core/test-utils'

import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {useChatState, useChatStateValues} from '../../utils/CopilotChatContext'
import {useSelectedCustomCopilotId} from '../use-selected-custom-copilot-id'
import {useSupportedAttachmentTypes} from '../use-supported-attachment-types'

jest.mock('../../utils/CopilotChatContext')
jest.mock('../use-selected-custom-copilot-id')

const mockUseChatState = useChatState as jest.Mock
const mockUseChatStateValues = useChatStateValues as jest.Mock
const mockUseSelectedCustomCopilotId = useSelectedCustomCopilotId as jest.Mock

describe('useSupportedAttachmentTypes', () => {
  beforeEach(() => {
    jest.resetAllMocks()

    // Default mocks
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'repository', owner: 'test', repo: 'test-repo', ref: 'main'},
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    mockUseChatStateValues.mockReturnValue({
      model: {capabilities: {supports: {vision: true}}},
    })
    mockUseSelectedCustomCopilotId.mockReturnValue(null)

    jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(false)
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
  })

  test('returns default supported types when all features are enabled and not in a Copilot Space', () => {
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toEqual([
      'repositories',
      'references',
      'knowledge-bases',
      'upload',
      'agents',
    ])
    expect(result.current.supportedReferenceTypes).toEqual(['files', 'folders', 'symbols'])
  })

  test('returns correct types when in a Copilot Space', () => {
    mockUseSelectedCustomCopilotId.mockReturnValue('some-copilot-id')
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toEqual(['references', 'upload'])
    expect(result.current.supportedReferenceTypes).toEqual(['files'])
  })

  test('excludes references when topicsAsReferences is false and currentTopic is not set', () => {
    jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(false)
    mockUseChatState.mockReturnValue({
      currentTopic: null,
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).not.toContain('references')
  })

  test('includes references when topicsAsReferences is true, even if currentTopic is not set', () => {
    jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(true)
    mockUseChatState.mockReturnValue({
      currentTopic: null,
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toContain('references')
  })

  test('excludes knowledge-bases when renderKnowledgeBases is false', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'repository', owner: 'test', repo: 'test-repo', ref: 'main'},
      renderKnowledgeBases: false,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).not.toContain('knowledge-bases')
  })

  test('excludes knowledge-bases when currentTopic is not a repository and not null', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'docset', sourceRepos: []}, // Ensures isRepository returns false
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    const {result} = renderHook(() => useSupportedAttachmentTypes())
    // references is also excluded in this case by default mock for topicsAsReferences
    expect(result.current.supportedAttachmentTypes).toEqual(['repositories', 'upload', 'agents'])
  })

  test('includes knowledge-bases when currentTopic is null', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: null,
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: true}}},
    })
    const {result} = renderHook(() => useSupportedAttachmentTypes())
    // references is also excluded in this case by default mock for topicsAsReferences
    expect(result.current.supportedAttachmentTypes).toEqual(['repositories', 'knowledge-bases', 'upload', 'agents'])
  })

  test('excludes upload when both image and text uploads are disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).not.toContain('upload')
  })

  test('includes upload when only image uploads are enabled', () => {
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toContain('upload')
  })

  test('includes upload when only text uploads are enabled', () => {
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toContain('upload')
  })

  test('excludes image upload when mode is not immersive', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'repository', owner: 'test', repo: 'test-repo', ref: 'main'},
      renderKnowledgeBases: true,
      mode: 'panel', // Not immersive
      model: {capabilities: {supports: {vision: true}}},
    })
    // text uploads still enabled by default
    const {result} = renderHook(() => useSupportedAttachmentTypes())
    expect(result.current.supportedAttachmentTypes).toContain('upload') // because text is enabled

    // Disable text uploads to isolate image upload logic
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    const {result: result2} = renderHook(() => useSupportedAttachmentTypes())
    expect(result2.current.supportedAttachmentTypes).not.toContain('upload')
  })

  test('excludes image upload when model does not support vision', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'repository', owner: 'test', repo: 'test-repo', ref: 'main'},
      renderKnowledgeBases: true,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: false}}}, // No vision support
    })
    mockUseChatStateValues.mockReturnValue({
      model: {capabilities: {supports: {vision: false}}},
    })
    // text uploads still enabled by default
    const {result} = renderHook(() => useSupportedAttachmentTypes())
    expect(result.current.supportedAttachmentTypes).toContain('upload') // because text is enabled

    // Disable text uploads to isolate image upload logic
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    const {result: result2} = renderHook(() => useSupportedAttachmentTypes())
    expect(result2.current.supportedAttachmentTypes).not.toContain('upload')
  })

  test('scenario: Copilot Space with only text uploads enabled', () => {
    mockUseSelectedCustomCopilotId.mockReturnValue('some-copilot-id')
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
    // referencesEnabled will be true because topicsAsReferences is false by default, and isRepository is true by default mock
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toEqual(['references', 'upload'])
    expect(result.current.supportedReferenceTypes).toEqual(['files'])
  })

  test('scenario: Copilot Space with no upload capabilities', () => {
    mockUseSelectedCustomCopilotId.mockReturnValue('some-copilot-id')
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toEqual(['references'])
    expect(result.current.supportedReferenceTypes).toEqual(['files'])
  })

  test('scenario: Not in Copilot Space, no vision, no text upload, no knowledge base, not repo topic', () => {
    mockUseChatState.mockReturnValue({
      currentTopic: {type: 'docset', sourceRepos: []}, // Ensures isRepository returns false
      renderKnowledgeBases: false,
      mode: 'immersive',
      model: {capabilities: {supports: {vision: false}}},
    })
    mockUseChatStateValues.mockReturnValue({
      model: {capabilities: {supports: {vision: false}}},
    })
    jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true) // image upload FF enabled
    jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
    jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(false)
    const {result} = renderHook(() => useSupportedAttachmentTypes())

    expect(result.current.supportedAttachmentTypes).toEqual(['repositories', 'agents'])
    expect(result.current.supportedReferenceTypes).toEqual(['files', 'folders', 'symbols'])
  })
})
