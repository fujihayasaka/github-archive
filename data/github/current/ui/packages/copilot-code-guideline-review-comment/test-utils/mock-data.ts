import type {CopilotCodeGuidelineReviewCommentProps} from '../CopilotCodeGuidelineReviewComment'

export function getCopilotCodeGuidelineReviewCommentProps(): CopilotCodeGuidelineReviewCommentProps {
  return {
    threadSubject: {
      diffLines: [
        {__id: '1', left: null, right: 0, type: 'HUNK', html: '@@ -0,0 +1,6 @@', text: '@@ -0,0 +1,6 @@'},
        {
          __id: '2',
          // eslint-disable-next-line github/unescaped-html-literal
          html: '<span class=pl-k>class</span> <span class=pl-v>StateManager</span>',
          text: '+class StateManager',
          type: 'ADDITION',
          left: null,
          right: 1,
        },
      ],
      endLine: 1,
      endDiffSide: 'RIGHT',
      originalEndLine: 1,
      originalStartLine: 1,
      pullRequestCommit: {
        commit: {
          abbreviatedOid: 'abc123',
        },
      },
      startDiffSide: 'LEFT',
      startLine: 1,
      path: 'path/to/file.txt',
      isResolved: false,
      pullRequestId: '1',
      id: '1',
    },
    thread: {
      commentsData: {comments: []},
      diffSide: 'RIGHT',
      id: 'abc',
      isOutdated: false,
      isResolved: false,
      subject: {
        diffLines: [
          {__id: '1', left: null, right: 0, type: 'HUNK', html: '@@ -0,0 +1,6 @@', text: '@@ -0,0 +1,6 @@'},
          {
            __id: '2',
            // eslint-disable-next-line github/unescaped-html-literal
            html: '<span class=pl-k>class</span> <span class=pl-v>StateManager</span>',
            text: '+class StateManager',
            type: 'ADDITION',
            left: null,
            right: 1,
          },
        ],
        endLine: 1,
        endDiffSide: 'RIGHT',
        originalEndLine: 1,
        originalStartLine: 1,
        pullRequestCommit: {
          commit: {
            abbreviatedOid: 'abc123',
          },
        },
        startDiffSide: 'LEFT',
        startLine: 1,
      },
      viewerCanReply: false,
      subjectType: 'LINE',
    },
    comment: {
      author: {
        avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
        login: 'monalisa',
        id: 'monalisabla',
        url: 'https://github.com/monalisa',
      },
      authorAssociation: 'NONE',
      body: 'You did something against the guideline',
      // eslint-disable-next-line github/unescaped-html-literal
      bodyHTML: '<p>You did something against the guideline</p>',
      createdAt: '2023-01-01T00:00:00Z',
      publishedAt: '2023-01-01T00:00:00Z',
      lastUserContentEdit: null,
      currentDiffResourcePath: 'path/to/file.txt',
      id: 'aaa',
      databaseId: 2,
      isHidden: false,
      minimizedReason: null,
      outdated: false,
      reference: {
        number: 1,
        text: 'abc123',
        author: {
          login: 'monalisa',
        },
      },
      repository: {
        isPrivate: false,
        id: 'abc',
        name: 'repo',
        owner: {
          login: 'monalisa',
          id: 'monalisabla',
          url: 'https://github.com/monalisa/abc',
        },
      },
      state: 'PUBLISHED',
      viewerCanBlockFromOrg: false,
      viewerCanMinimize: false,
      viewerCanSeeMinimizeButton: false,
      viewerCanSeeUnminimizeButton: false,
      viewerCanReport: false,
      viewerCanReportToMaintainer: false,
      viewerCanUnblockFromOrg: false,
      viewerDidAuthor: false,
      viewerRelationship: 'NONE',
      url: 'https://github.com/path/to/comment/abc123',
      viewerCanDelete: false,
      viewerCanUpdate: false,
    },
  }
}
