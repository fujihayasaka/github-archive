import {CommentsPreference} from '@github-ui/diff-view-settings/types'
import type {FilesRoutePayload} from '../page-data/payloads/files'
import {getHeaderPageData} from './header-mock-data'
import {getPullRequestFilesToolbarMockData} from '@github-ui/pull-request-files-toolbar/mock-data'

export function getFilesRoutePayload(): FilesRoutePayload {
  const toolbarData = getPullRequestFilesToolbarMockData()
  const headerData = getHeaderPageData()

  return {
    commits: [
      {
        actorLogin: 'mock-actor',
        createdAt: '2022-01-01T00:00:00Z',
        messageHeadline: 'Mock commit message',
        shortOid: 'abc123',
        oid: 'abc123',
      },
    ],
    diffSummaries: [],
    diffContents: [],
    ...toolbarData,
    ...headerData,
    pullRequest: {
      ...headerData.pullRequest,
      ...toolbarData.pullRequest,
    },
    repository: {
      ...toolbarData.pullRequest.repository,
      ...headerData.repository,
    },
    user: {
      ...headerData.user,
      currentUserLogin: toolbarData.currentUserLogin,
      isFileTreeExpanded: toolbarData.isFileTreeExpanded,
      shouldShowViewedFilesCount: toolbarData.shouldShowViewedFilesCount,
      viewedFilesCount: toolbarData.viewedFilesCount,
      viewSettings: {
        hideWhitespace: false,
        splitPreference: 'split',
        lineSpacing: 'compact',
        commentsPreference: CommentsPreference.Visible,
      },
    },
  }
}
