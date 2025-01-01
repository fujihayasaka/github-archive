import type {CopilotChatProps} from '../CopilotChat'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import {
  type CodeNavSymbolReference,
  type CopilotChatMessage,
  type CopilotChatMode,
  type CopilotChatModel,
  type CopilotChatReference,
  type CopilotChatRepo,
  type CopilotChatThread,
  CopilotLicenseType,
  type DiscussionReference,
  type Docset,
  type FileReference,
  type ImageReference,
  type IssueReference,
  type MessageStreamingResponseComplete,
  type PullRequestReference,
  type RepositoryReference,
  type SnippetReference,
  type ThirdPartyReference,
} from '../utils/copilot-chat-types'
import type {CopilotChatProviderProps} from '../utils/CopilotChatContext'
import {generateDefaultModel} from '../utils/models'
import {Base64FileAttachment, type DotcomFileAttachment} from '../utils/uploadable-file-attachment'

export function getCopilotChatProps(): CopilotChatProps {
  return {
    currentUserLogin: 'monalisa',
    apiURL: 'https://github.com/github-copilot/chat',
    currentTopic: getRepositoryMock(),
    findFileWorkerPath: '@/find-file-worker.js',
    ssoOrganizations: [],
    agentsPath: '/agents',
    optedInToUserFeedback: true,
    reviewLab: false,
    realIp: '127.0.0.1',
    hasCEorCBAccess: false,
    licenseType: CopilotLicenseType.LicensedFull,
    optedInToPreviewFeatures: true,
    customCopilotsEnabled: true,
  }
}

export function getCopilotChatProviderProps(): CopilotChatProviderProps {
  return {
    ssoOrganizations: [],
    topic: getRepositoryMock(),
    workerPath: '@/find-file-worker.js',
    threadId: '0',
    refs: [],
    mode: 'assistive',
    realIp: '127.0.0.1',
    copilotChatPayload: {
      agentsPath: '/agents',
      apiURL: 'apiURL',
      currentUserLogin: 'currentUserLogin',
      hasCEorCBAccess: false,
      licenseType: CopilotLicenseType.LicensedFull,
      optedInToPreviewFeatures: true,
      optedInToUserFeedback: true,
      reviewLab: false,
      autoSubmit: true,
      customCopilotsEnabled: true,
    },
  }
}

export function getDefaultReducerState(
  threadId: string | null,
  topic: CopilotChatRepo | undefined,
  mode: CopilotChatMode,
): CopilotChatState {
  const defaultModel: CopilotChatModel = generateDefaultModel()
  return {
    ssoOrganizations: [],
    threadsLoading: {state: 'pending', error: null},
    messagesLoading: {state: 'pending', error: null},
    slashCommandLoading: {state: 'pending', error: null},
    knowledgeBasesLoading: {state: 'pending', error: null},
    personalInstructions: null,
    knowledgeBases: [],
    model: defaultModel,
    availableModels: [defaultModel],
    modelsLoading: {state: 'pending', error: null},
    showTopicPicker: false,
    topicLoading: {state: 'pending', error: null},
    threads: new Map<string, CopilotChatThread>(),
    messages: [],
    messagesRestored: false,
    streamingMessage: null,
    selectedThreadID: threadId,
    currentTopic: topic,
    chatIsOpen: false,
    isWaitingOnCopilot: false,
    isWaitingOnAttachment: false,
    currentUserLogin: 'currentUserLogin',
    apiUrl: 'apiURL',
    currentReferences: [],
    findFileWorkerPath: 'workerPath',
    currentView: 'thread',
    selectedReference: null,
    mode,
    topRepositoriesCache: undefined,
    agents: [],
    agentsPath: '/agents',
    optedInToPreviewFeatures: true,
    optedInToUserFeedback: true,
    reviewLab: false,
    repoCustomInstructionsEnabled: true,
    customCopilotsEnabled: true,
    ambientError: null,
    threadHasNewMessages: false,
    sharedThreadsLoading: {state: 'pending', error: null},
  }
}

export function getReducerStateMock(): CopilotChatState {
  const defaultModel: CopilotChatModel = generateDefaultModel()
  return {
    ssoOrganizations: [],
    threadsLoading: {state: 'pending', error: null},
    messagesLoading: {state: 'pending', error: null},
    slashCommandLoading: {state: 'pending', error: null},
    knowledgeBasesLoading: {state: 'pending', error: null},
    personalInstructions: null,
    knowledgeBases: [],
    model: defaultModel,
    availableModels: [defaultModel],
    modelsLoading: {state: 'pending', error: null},
    showTopicPicker: false,
    topicLoading: {state: 'pending', error: null},
    threads: new Map<string, CopilotChatThread>(),
    messages: [],
    messagesRestored: false,
    streamingMessage: null,
    selectedThreadID: 'threadId',
    currentTopic: {
      id: 1,
      name: 'github',
      ownerLogin: 'github',
      ownerType: 'Organization',
      commitOID: '1234',
      ref: 'refs/heads/main',
      refInfo: {
        name: 'main',
        type: 'branch',
      },
      visibility: 'public',
    },
    chatIsOpen: false,
    isWaitingOnCopilot: false,
    isWaitingOnAttachment: false,
    currentUserLogin: 'login',
    apiUrl: 'apiURL',
    currentReferences: [],
    findFileWorkerPath: 'workerPath',
    currentView: 'thread',
    mode: 'assistive',
    selectedReference: null,
    topRepositoriesCache: undefined,
    agents: [],
    optedInToPreviewFeatures: true,
    optedInToUserFeedback: true,
    reviewLab: false,
    repoCustomInstructionsEnabled: true,
    customCopilotsEnabled: true,
    ambientError: null,
    threadHasNewMessages: false,
    sharedThreadsLoading: {state: 'pending', error: null},
  }
}

export function getSymbolReferenceMock(): CodeNavSymbolReference {
  return {
    type: 'symbol',
    kind: 'codeNavSymbol',
    name: 'name',
    codeNavDefinitions: [
      {
        ident: {
          start: {line: 1, column: 1},
          end: {line: 1, column: 1},
        },
        extent: {
          start: {line: 1, column: 1},
          end: {line: 1, column: 1},
        },
        kind: 'kind',
        fullyQualifiedName: 'fullyQualifiedName',
        repoID: 1,
        repoOwner: 'repoOwner',
        repoName: 'repoName',
        ref: 'ref',
        commitOID: 'commitOID',
        path: 'path',
      },
    ],
    codeNavReferences: [],
  }
}

export function getRepositoryReferenceMock(
  ownerLogin: string = 'Owner',
  name: string = 'Repository',
): RepositoryReference {
  return {
    id: 1,
    name,
    ownerLogin,
    ownerType: 'User',
    type: 'repository',
    commitOID: '1234',
    ref: 'refs/heads/main',
    refInfo: {
      name: 'main',
      type: 'branch',
    },
    visibility: 'private',
  }
}

export function getSnippetReferenceMock(): SnippetReference {
  return {
    type: 'snippet',
    url: 'https://github.com',
    path: '/path/to/file',
    repoID: 123,
    repoOwner: 'owner',
    repoName: 'repo',
    ref: '1234',
    commitOID: '5678',
    range: {
      start: 1,
      end: 5,
    },
  }
}

export function getImageReferenceMock(blobContentsOfAttachment?: string[]): ImageReference {
  const id = crypto.randomUUID()
  return {
    type: 'image',
    mediaType: 'image/png',
    imageUrl: 'data:image/jpeg;base64,',
    name: 'image.png',
    attachment: getMockImageAttachment(
      id,
      blobContentsOfAttachment || ['Sample content'],
      'image/png',
      'image.png',
      'data:image/jpeg;base64,',
    ),
    id,
  }
}

export function getIssueReferenceMock(
  issueNum: string = '1234',
  repo: string = 'copilot-chat',
  owner: string = 'github',
): IssueReference {
  return {
    type: 'issue',
    id: Number(issueNum),
    number: Number(issueNum),
    repository: {
      id: Number(issueNum),
      name: repo,
      owner,
    },
    title: 'This is a test issue',
    url: `https://github.com/${owner}/${repo}/issues/${issueNum}`,
  }
}

export function getDiscussionReferenceMock(
  issueNum: string = '1234',
  repo: string = 'copilot-chat',
  owner: string = 'github',
): DiscussionReference {
  return {
    type: 'discussion',
    id: Number(issueNum),
    number: Number(issueNum),
    body: 'This is a test discussion',
    user: {
      login: 'mona',
    },
    authorLogin: 'mona',
    state: 'open',
    repository: {
      id: Number(issueNum),
      name: repo,
      owner,
    },
    title: 'This is a test discussion',
    url: `https://github.com/${owner}/${repo}/discussions/${issueNum}`,
  }
}

export function getFileReferenceMock(
  ref: string,
  path: string,
  repo: string = 'copilot-chat',
  owner: string = 'github',
): FileReference {
  return {
    type: 'file',
    commitOID: '123ABC',
    path,
    ref,
    repoID: 123,
    repoName: repo,
    repoOwner: owner,
    url: `https://github.com/${owner}/${repo}/tree/${ref}/${path}`,
  }
}

export function getPullRequestReferenceMock(
  num: string = '1234',
  repo: string = 'copilot-chat',
  owner: string = 'github',
): PullRequestReference {
  return {
    type: 'pull-request',
    id: Number(num),
    number: Number(num),
    repository: {
      ...getRepositoryMock(),
      id: Number(num),
      name: repo,
      ownerLogin: owner,
    },
    title: 'This is a test pull request',
    url: `https://github.com/${owner}/${repo}/pull/${num}`,
    authorLogin: 'monalisa',
  }
}

export function getMockImageAttachment(
  id: string,
  blobContentsOfAttachment: string[],
  mediaType: string,
  name: string,
  imageUrl: string,
): DotcomFileAttachment {
  const blob = new Blob(blobContentsOfAttachment, {type: mediaType})
  const file: File = new File([blob], name, {
    type: mediaType,
    lastModified: Date.now(),
  })
  const attachment = new Base64FileAttachment(id, file)
  attachment.url = jest.fn().mockResolvedValue(imageUrl)

  return attachment
}

export function getThreadMock(): CopilotChatThread {
  return {
    id: '0',
    name: 'thread',
    currentReferences: [],
    createdAt: '2020-01-01T00:00:00Z',
    updatedAt: '2020-01-01T00:00:00Z',
  }
}

export function getMessageMock(): CopilotChatMessage {
  return {
    id: '0',
    role: 'user',
    content: 'content',
    createdAt: '2020-01-01T00:00:00Z',
    threadID: '0',
    references: [],
  }
}

export function getMessageStreamingResponseMock(): MessageStreamingResponseComplete {
  return {
    type: 'complete',
    id: '0',
    turnId: '0',
    createdAt: '2020-01-01T00:00:00Z',
    references: [],
    intent: 'conversation',
    model: 'gpt-4',
    role: 'assistant',
  }
}

export function getRepositoryMock(): CopilotChatRepo {
  return {
    id: 1,
    name: 'github',
    ownerLogin: 'github',
    ownerType: 'Organization',
    commitOID: '1234',
    ref: 'refs/heads/main',
    refInfo: {
      name: 'main',
      type: 'branch',
    },
    visibility: 'public',
  }
}
export function getThirdPartyReferenceMock(props?: Partial<ThirdPartyReference>): CopilotChatReference {
  return {
    displayName: 'Third party reference display name',
    displayIcon: 'https://example.com/example.png',
    displayUrl: 'https://example.com/example.html',
    ...props,
    type: 'third-party',
    data: '',
  }
}

export function getReferencesMock(): CopilotChatReference[] {
  return [
    {
      type: 'snippet',
      repoID: 1,
      repoOwner: 'github',
      repoName: 'github',
      ref: 'main',
      commitOID: 'abcdef',
      range: {start: 1, end: 10},
      title: 'bing',
      path: '/bing',
      url: 'http://bing.com',
    },
    {
      type: 'snippet',
      repoID: 1,
      repoOwner: 'github',
      repoName: 'github',
      ref: 'main',
      commitOID: 'abcdef',
      range: {start: 1, end: 10},
      title: 'google',
      path: '/google',
      url: 'http://google.com',
    },
    {
      type: 'snippet',
      repoID: 1,
      repoOwner: 'github',
      repoName: 'github',
      ref: 'main',
      commitOID: 'abcdef',
      range: {start: 1, end: 10},
      title: 'altavista',
      path: '/altavista',
      url: 'http://altavista.com',
    },
    {
      type: 'snippet',
      repoID: 1,
      repoOwner: 'github',
      repoName: 'github',
      ref: 'main',
      commitOID: 'abcdef',
      range: {start: 1, end: 10},
      title: 'lycos',
      path: '/lycos',
      url: 'http://lycos.com',
    },
  ]
}

export function getDocsetMock(props?: Partial<Docset>): Docset {
  return {
    id: '6cacfde5-0363-4cf0-b8ff-c057c04ffb48',
    name: 'GitHub Engineering',
    createdByID: 1149246,
    ownerID: 9919,
    ownerType: 'organization',
    repos: [
      'github/blackbird',
      'github/delivery-org',
      'github/deploys',
      'github/github',
      'github/heaven',
      'github/hubbernetes',
      'github/ops',
      'github/thehub',
    ],
    sourceRepos: [
      {
        id: 1,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 2,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 3,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 4,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 5,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 6,
        ownerID: 9919,
        paths: [],
      },
      {
        id: 7,
        ownerID: 19919,
        paths: [],
      },
      {
        id: 8,
        ownerID: 9919,
        paths: ['/^docs\\/epd\\/engineering\\//'],
      },
    ],
    visibility: 'private',
    adminableByUser: false,
    avatarUrl: 'https://avatars.githubusercontent.com/u/9919?v=4',
    ownerLogin: 'github',
    protectedOrganizations: [],
    description: '',
    visibleOutsideOrg: false,
    canChat: true,
    ...props,
  }
}

export function getModelMock(): CopilotChatModel {
  return generateDefaultModel()
}
