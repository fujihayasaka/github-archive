import type {WebCommitInfo} from '@github-ui/code-view-types'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {TokenUsage} from '@github-ui/github-models'
import type {RefInfo} from '@github-ui/repos-types'
import type {EvaluatorLLM} from '../routes/prompt/evals-sdk/config'
import type {CompareState, PromptCompareState} from '../routes/prompt/prompt-compare-state'
import type {PromptConfig} from '../routes/prompt/prompts'
import type {PromptAppPayload, PromptInfo, ReviewAppPayload} from '../routes/prompt/types'
import type {
  ModelRepoPayload,
  ModelRepoPromptsAppPayload,
  ModelRepoPromptsRoutePayload,
  ParsedPrompt,
  RepoModel,
} from '../types'

export function mockPromptCompareState(
  overrides: Partial<Omit<PromptCompareState, 'compare'>> & {compare?: Partial<CompareState>} = {},
): PromptCompareState {
  const prompts = overrides.prompts || [{messages: []}]
  const baseCompare: CompareState = {
    isRunning: false,
    rows: [],
    skippedRowIds: new Set<string>(),
    result: {},
    evaluators: [],
  }
  const compare = overrides.compare ? {...baseCompare, ...overrides.compare} : baseCompare
  const messages = overrides.messages || []
  const variables = overrides.variables || {}
  return {
    prompts,
    messages,
    variables,
    compare,
    isLoading: overrides.isLoading || false,
  }
}

export function mockPromptConfig(overrides: Partial<PromptConfig> = {}): PromptConfig {
  const defaults: PromptConfig = {
    path: 'my.prompt.yml',
    model: 'gpt-4o',
    messages: [
      {role: 'system', message: 'You explain concepts', timestamp: new Date()},
      {role: 'user', message: 'How does {{topic}} work?', timestamp: new Date()},
    ],
  }
  return {...defaults, ...overrides}
}

export function mockTokenUsage(overrides: Partial<TokenUsage> = {}): TokenUsage {
  const defaults: TokenUsage = {
    lastMessageInputTokens: 0,
    lastMessageOutputTokens: 0,
    totalInputTokens: 0,
    totalOutputTokens: 0,
    lastMessageLatency: 0,
  }
  return {...defaults, ...overrides}
}

export function mockModel(overrides: Partial<RepoModel> = {}): RepoModel {
  const defaults: RepoModel = {
    id: 'azureml://registries/azure-openai/models/my-test-model-original/versions/2024-11-20',
    registry: 'azureopenai',
    name: 'my-test-model',
    original_name: 'my-test-model-original',
    friendly_name: 'My Test Model',
    publisher: 'openai',
    task: 'chat-completion',
    summary: 'Use this model to do stuff.',
    logo_url: 'http://example.com/logo.png',
    // in real-world use these are base64 encoded svg strings, they are shortened here for readability
    light_mode_icon: 'dayModejaisdflj',
    dark_mode_icon: 'nightModejaisdflj',
    publisherSlug: 'openai',
    capabilities: {
      streaming: false,
      structuredOutput: false,
      systemPrompt: false,
      tokenCounting: false,
    },
  }
  return {...defaults, ...overrides}
}

export const mockOrgAllowedModel: RepoModel = {
  id: 'azureml://registries/azureopenai/models/org-allowed-model/versions/2024-11-20',
  registry: 'azureopenai',
  name: 'org-allowed-model',
  original_name: 'org-allowed-model',
  friendly_name: 'Org Allowed Model',
  publisher: 'Open AI',
  task: 'chat-completion',
  summary: 'Use this model to do stuff.',
  logo_url: 'http://example.com/logo.png',
  light_mode_icon: '',
  dark_mode_icon: '',
  publisherSlug: 'openai',
}

export const mockModels: RepoModel[] = [
  mockOrgAllowedModel,
  mockModel({
    id: `${mockOrgAllowedModel.id}-2`,
    name: 'model-2',
    friendly_name: 'Model 2',
  }),
  mockModel({
    id: `${mockOrgAllowedModel.id}-3`,
    name: 'model-3',
    friendly_name: 'Really Quite A Very Long Model Name You Would Not Believe',
  }),
  mockModel({
    id: `${mockOrgAllowedModel.id}-4`,
    name: 'model-4-o1-mini',
    friendly_name: 'An O1 Mini Model',
  }),
]

export const mockWebCommitInfo: WebCommitInfo = {
  authorEmails: ['test1@test.com', 'test2@test.com'],
  canCommitStatus: 'allowed',
  commitOid: '',
  dcoSignoffEnabled: false,
  defaultEmail: 'test2@test.com',
  defaultNewBranchName: 'patch-1',
  forkedRepo: undefined,
  lockedOnMigration: false,
  userOverRepositoryLimit: false,
  pr: '',
  repoHeadEmpty: false,
  saveUrl: 'testUrl',
  shouldFork: false,
  shouldUpdate: false,
  suggestionsUrlEmoji: '',
  suggestionsUrlIssue: '',
  suggestionsUrlMention: '',
}

const refInfo: RefInfo = {
  name: 'main',
  listCacheKey: 'test',
  canEdit: false,
  currentOid: '',
}

export const mockCommitInfo = {
  webCommitInfo: mockWebCommitInfo,
  refInfo,
  fileSaveAuthenticityToken: 'token',
}

// Generate a list of prompts with the given names
const generatePrompts = (names: string[]): ParsedPrompt[] => {
  return names.map(name => ({
    name,
    description: `This is a description for ${name}`,
    path: `prompts/${name}.md`,
    model: 'gpt-4',
  }))
}

export function mockPromptInfo(overrides: Partial<PromptInfo> = {}): PromptInfo {
  const defaults: PromptInfo = {
    path: 'fave.prompt.yml',
    content: 'foo',
    ref: 'main',
    sha: '6d4fb557715fec7134f7ca9673464e0c492549f2',
  }
  return {...defaults, ...overrides}
}

export function getReviewAppPayload(): ReviewAppPayload {
  return {
    payload: {
      inferenceUrl: 'https://inference.url',
      restrictedModels: [],
      repository: createRepository(),
      pull: {
        number: 123,
        title: 'My Best Changes',
      },
      basePrompt: mockPromptInfo({ref: 'main', content: 'foo'}),
      headPrompt: mockPromptInfo({ref: 'feature-branch', content: 'foo 2'}),
    },
  }
}

export function getModelRepoPromptsRoutePayload(promptNames: string[] = []): ModelRepoPromptsRoutePayload {
  return {
    prompts: generatePrompts(promptNames),
    page: 1,
    totalPages: 1,
  }
}

export function getModelRepoPromptsAppPayload(
  overrides: Partial<ModelRepoPromptsAppPayload> = {},
): ModelRepoPromptsAppPayload {
  const defaults: ModelRepoPromptsAppPayload = {
    repository: createRepository(),
    canEdit: true,
    restrictedModels: [],
    totalPrompts: 0,
  }
  return {...defaults, ...overrides}
}

export function getModelsRoutePayload(promptNames: string[] = []): ModelRepoPayload {
  return {
    repository: createRepository(),
    prompts: generatePrompts(promptNames),
    canEdit: true,
    totalPrompts: promptNames.length,
    restrictedModels: [],
    sampleActionsUrl:
      'https://github.blog/changelog/2025-04-14-github-actions-token-integration-now-generally-available-in-github-models/',
    compareModelsUrl: 'org/repo/models/registry/model1/playground?compare_to=model2',
    onboardingVideoBannerDismissed: false,
  }
}

export function getPromptAppPayload(initialValues?: {payload?: object}): PromptAppPayload {
  const {payload, ...rest} = initialValues || {}

  return {
    payload: {
      inferenceUrl: 'https://inference.url',
      restrictedModels: [],
      prompt: `name: 'Test Prompt'
description: 'This is a test prompt'
model: 'gpt-4'
messages:
  - role: system
    content: 'System prompt'
  - role: user
    content: 'User prompt'`,
      promptPath: 'prompt.prompt.yml',
      promptRef: 'main',
      repository: createRepository(),
      commitInfo: mockCommitInfo,
      canEdit: true,
      ...payload,
    },
    ...rest,
  }
}

export function mockResizeObserver() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', {writable: true, configurable: true, value: MockResizeObserver})
}

export function mockEvaluatorLLM(overrides: Partial<EvaluatorLLM> = {}) {
  const defaults: EvaluatorLLM = {
    model: 'gpt-4o',
    modelId: 'azureml://registries/azure-openai/models/gpt-4o',
    modelParameters: {temperature: 0.5},
    prompt: "You're in a desert, walking along in the sand",
    systemPrompt: 'Only reply in all caps.',
    choices: [
      {choice: '1', score: 0},
      {choice: '2', score: 0.25},
    ],
  }
  return {...defaults, ...overrides}
}
