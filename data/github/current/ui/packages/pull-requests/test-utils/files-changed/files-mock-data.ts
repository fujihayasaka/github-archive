import {CommentsPreference, DiffLineSpacingPreference, SplitPreference} from '@github-ui/diff-view-settings/types'
import type {DiffUser} from '@github-ui/diff-lines/types'
import type {FilesRoutePayload} from '../../page-data/payloads/files'
import {getHeaderPageData} from '../header-mock-data'
import {getPullRequestFilesToolbarMockData} from './toolbar-mock-data'
import {getFilesRoutePullRequest, getFilesRouteRepository} from './pull-request-mock-data'
import {getMockFileFilterPageData} from './file-filter-mock-data'

export function getFilesRoutePayload(): FilesRoutePayload {
  const toolbarData = getPullRequestFilesToolbarMockData()
  const headerData = getHeaderPageData()
  const fileFilterData = getMockFileFilterPageData()

  return {
    viewerPendingReview: {
      id: 'test-id',
      comments: [],
    },
    diffSummaries: [],
    diffContents: [],
    fileFilter: {
      initialState: fileFilterData.fileFilterState,
      menuOptions: fileFilterData.fileFilterMenuOptions,
    },
    ...toolbarData,
    ...headerData,
    commits: [
      {
        actorLogin: 'mock-actor',
        createdAt: '2022-01-01T00:00:00Z',
        messageHeadline: 'Mock commit message',
        shortOid: 'abc123',
        oid: 'abc123',
      },
    ],
    markers: {threads: [], annotations: []},
    pageLimits: {
      annotationsLimit: 50,
      annotationsLimitExceeded: false,
      filesLimit: 300,
      filesLimitExceeded: false,
      reviewThreadsLimit: 40,
      reviewThreadsLimitExceeded: false,
    },
    pullRequest: getFilesRoutePullRequest(),
    repository: getFilesRouteRepository(),
    user: {
      ...headerData.user,
      canComment: true,
      currentUserLogin: toolbarData.currentUserLogin,
      hasCopilotAccess: true,
      isFileTreeExpanded: true,
      shouldShowViewedFilesCount: toolbarData.shouldShowViewedFilesCount,
      viewedFilesCount: toolbarData.viewedFilesCount,
      canApplySuggestion: true,
      commentingSettings: {...toolbarData.commentBoxConfig, emojiSkinTonePreference: 0},
      viewSettings: {
        hideWhitespace: false,
        splitPreference: currentUserMockData.splitPreference,
        lineSpacing: currentUserMockData.lineSpacing,
        commentsPreference: currentUserMockData.commentsPreference,
      },
    },
  }
}

export const currentUserMockData: DiffUser = {
  avatarURL: 'https://avatars.githubusercontent.com/u/12345',
  login: 'monalisa',
  tabSize: 4,
  splitPreference: SplitPreference.Split,
  lineSpacing: DiffLineSpacingPreference.Compact,
  canComment: true,
  commentsPreference: CommentsPreference.Visible,
  hasCopilotAccess: true,
  canApplySuggestion: true,
}
