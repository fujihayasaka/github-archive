import type {DirectoryItem} from '@github-ui/code-view-types'
import {getRepositoryMock} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {Repository} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {RefInfo} from '@github-ui/repos-types'
import type {SafeHTMLString} from '@github-ui/safe-html'

import type {FilesContextData} from '../contexts/FilesContext'
import {DiffCategory, type GroupedDiffs} from '../utilities/diff-analysis'
import type {GeneratedFix} from '../utilities/generate-fix-helpers'
import {
  type FocusedGenerativeTaskData,
  type OverviewPayload,
  TaskTypes,
  type WorkspaceEditorPullRequestPayload,
  type WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'

export function getWorkspaceEditorRoutePayload(
  overrides: Partial<WorkspaceEditorRoutePayload> = {},
): WorkspaceEditorRoutePayload & WorkspaceEditorPullRequestPayload {
  const repo: Repository = createRepository()
  const readme: DirectoryItem = {
    name: 'readme',
    contentType: 'file',
    hasSimplifiedPath: false,
    path: 'readme',
  }

  return {
    currentUser: {
      id: 1,
      login: 'monalisa',
      userEmail: 'monalisa@github.com',
    },
    fileTree: {'': {items: [readme], totalCount: 1}},
    diffPaths: {'': {items: [readme], totalCount: 1}},
    fileTreeProcessingTime: 1,
    foldersToFetch: [],
    path: 'readme',
    refInfo: {
      name: 'main',
      listCacheKey: 'key',
      canEdit: true,
      currentOid: 'abcd12345face398f34f3b7b7db142a0724fa958',
    } as RefInfo,
    repo,
    copilotAccessAllowed: true,
    pullRequestNumber: '1',
    pullRequest: {
      id: '1',
      number: '1',
      title: 'PR title',
      headBranch: 'feature-branch',
      headSHA: 'abcd12345face398f34f3b7b7db142a0724fa958',
      baseBranch: 'main',
      isOpen: true,
      authorLogin: 'monalisa',
    },
    findFileWorkerPath: 'mock',
    webCommitInfo: {
      authorEmails: [],
      canCommitStatus: 'blocked',
      commitOid: '',
      dcoSignoffEnabled: false,
      defaultEmail: '',
      defaultNewBranchName: '',
      lockedOnMigration: false,
      pr: '',
      repoHeadEmpty: false,
      saveUrl: '',
      shouldFork: false,
      shouldUpdate: false,
      suggestionsUrlIssue: '/issue',
      suggestionsUrlEmoji: '/emoji',
      suggestionsUrlMention: '/mention',
    },
    helpUrl: '/help',
    copilot: {
      ssoOrganizations: [],
      agentsPath: '/agents',
      apiURL: '/api',
      currentUserLogin: 'monalisa',
      currentTopic: getRepositoryMock(),
      optedInToPreviewFeatures: true,
      optedInToUserFeedback: true,
      reviewLab: false,
      licenseType: CopilotLicenseType.LicensedFull,
    },
    editorSettings: {
      codeLineWrapEnabled: false,
      whitespaceHidden: false,
      problemsHidden: false,
    },
    large: false,
    isNewFilePage: false,
    ...overrides,
  }
}

export function getWorkspaceEditorOverviewPayload(): OverviewPayload {
  return {
    bodyHtml: 'PR body',
    titleHtml: 'PR title',
    labels: [{color: '000000', name: 'my label'}],
  }
}

export function getCategorizedDiffsPayload(): GroupedDiffs {
  return {
    [DiffCategory.Code]: [
      {
        isBinary: false,
        isTooBig: false,
        linesAdded: 1,
        linesDeleted: 1,
        linesChanged: 1,
        path: 'readme.md',
        status: 'MODIFIED',
        newTreeEntry: {mode: 100644, path: 'readme.md'},
        oldTreeEntry: {mode: 100644, path: 'readme.md'},
        diffLines: [
          {
            text: '-This is the original line',
            html: '-This is the original line',
            left: 1,
            right: 1,
            type: 'DELETION',
          },
          {
            text: '+This line is unchanged',
            html: '+This line is unchanged',
            left: 1,
            right: 2,
            type: 'DELETION',
          },
        ],
      },
    ],
  } as GroupedDiffs
}

export function getGenerativeTaskData(): FocusedGenerativeTaskData {
  const fillerCommentFields = {
    lineNumber: 1,
    side: 'RIGHT',
    commitOid: 'abcd123',
    diffHunk: '@@ -1,3 +1,4 @@\n This is the original line\n+Another new line added\n This line remains unchanged',
    originalCommitOid: 'abcd123',
    originalLineNumber: 1,
    originalStartLineNumber: 1,
    path: 'readme',
    sourceId: '1',
    startLineNumber: 1,
    startSide: 'RIGHT',
    subjectType: 'file',
    pullRequestId: 1,
  }

  return {
    comment: {
      author: {
        avatarUrl: '',
        displayLogin: 'monalisa',
      },
      body: 'comment 1 body',
      createdAt: '2022-02-02T00:00:00Z',
      updatedAt: '2022-02-02T00:00:00Z',
      id: 1,
      bodyText: 'comment 1 body',
      inReplyToId: undefined,
      type: TaskTypes.Generative,
      ...fillerCommentFields,
    },
    replies: [
      {
        author: {
          avatarUrl: '',
          displayLogin: 'contributor',
        },
        body: 'comment 2 body',
        createdAt: '2022-02-02T00:00:00Z',
        updatedAt: '2022-02-02T00:00:00Z',
        id: 2,
        bodyText: 'comment 2 body',
        inReplyToId: 1,
        type: TaskTypes.Generative,
        ...fillerCommentFields,
      },
      {
        author: {
          avatarUrl: '',
          displayLogin: 'rando',
        },
        body: 'comment 3 body',
        createdAt: '2022-02-02T00:00:00Z',
        updatedAt: '2022-02-02T00:00:00Z',
        id: 3,
        bodyText: 'comment 3 body',
        inReplyToId: 1,
        type: TaskTypes.Generative,
        ...fillerCommentFields,
      },
    ],
    html: '' as SafeHTMLString,
    outdated: false,
    path: 'readme',
    sourceId: 1,
    suggestions: [],
    type: TaskTypes.Generative,
    previousComments: [],
    followingComments: [],
  }
}

export function getGeneratedFix(overrides: Partial<GeneratedFix> = {}): GeneratedFix {
  return {
    description: 'Implement missing authorization check',
    gitPatch: `--- typescript.ts
+++ typescript.ts
@@ -1,2 +1,3 @@
-This is the original line
+This is the new line
+Another new line added
 This line remains unchanged`,
    targetFileCommitOid: 'abcd123',
    targetFilePath: 'typescript.ts',
    commentsVersion: '1643760000000',
    ...overrides,
  }
}

export function getFilesContextData(overrides: Partial<FilesContextData> = {}): FilesContextData {
  return {
    getNewFilePaths(): string[] {
      return []
    },
    addFile: jest.fn(),
    applyAllTaskSuggestionsToContent: jest.fn(),
    applySuggestionsToContent: jest.fn(),
    applyFileToContent: jest.fn(),
    deleteFile: jest.fn(),
    editFile: jest.fn(),
    getChangedFiles: jest.fn(),
    getCurrentFileContent: jest.fn(),
    getFileStatuses: jest.fn(),
    getFileTreeData: jest.fn(),
    markFilesCommitted: jest.fn(),
    renameFile: jest.fn(),
    resetFiles: jest.fn(),
    resetFile: jest.fn(),
    storeDiffs: jest.fn(),
    retrieveDiffs: jest.fn(),
    ...overrides,
  }
}
