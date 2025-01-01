import {mockSubmodule} from '@github-ui/diff-lines/mock-data'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {http, HttpResponse} from 'msw'

import type {CommitPayload, DiffEntryDataWithExtraInfo} from '../../types/commit-types'
import {getCommitRoutePayload} from '../commit-mock-data'

export const monalisa = {
  avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
  login: 'monalisa',
  url: '',
}

export const collaborator = {
  avatarUrl: 'http://alambic.github.localhost/avatars/u/156',
  login: 'collaborator',
  url: '',
}

export const relayIdFirstCommentForReactHelperRb = 'CC_a1b2'
const relayIdCreatedCommentForReactHelperRb = 'CC_a2b3'

export const initialCommentsForReactHelperRb = {
  comments: [
    {
      id: 1,
      relayId: relayIdFirstCommentForReactHelperRb,
      body: 'Why are we deleting this?',
      bodyVersion: '02b431982a1a5559d69b13c74d29b535e602aac57a4bfe8b3f56296d9aa0e58e',
      // eslint-disable-next-line github/unescaped-html-literal
      htmlBody: '<p dir="auto">Why are we deleting this?</p>' as SafeHTMLString,
      createdAt: '2024-12-02T14:57:44.000-08:00',
      updatedAt: '2024-12-02T14:57:44.000-08:00',
      lastUserContentEdit: null,
      path: 'app/helpers/react_helper.rb',
      position: 4,
      isHidden: false,
      viewerCanMinimize: {
        state: 'fulfilled',
        source: null,
        value: true,
      },
      minimizedReason: null,
      viewerCanDelete: true,
      viewerCanUpdate: true,
      viewerCanReport: true,
      viewerCanReportToMaintainer: false,
      viewerCanBlockFromOrg: false,
      viewerCanUnblockFromOrg: false,
      viewerDidAuthor: true,
      urlFragment: 'r1',
      viewerCanReadUserContentEdits: true,
      author: {
        id: 2,
        login: 'monalisa',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
      },
      authorAssociation: 'owner',
      threadId: 'app/helpers/react_helper.rb::4',
    },
  ],
}

const createdCommentForReactHelperRb = {
  id: 29,
  relayId: relayIdCreatedCommentForReactHelperRb,
  body: 'Should we really add this new component?',
  bodyVersion: '02b431982a1a5559d69b13c74d29b535e602aac57a4bfe8b3f56296d9aa0e58e',

  htmlBody: 'This code is no longer needed.',
  createdAt: new Date().toString(),
  updatedAt: new Date().toString(),
  lastUserContentEdit: null,
  path: 'app/helpers/react_helper.rb',
  position: 4,
  isHidden: false,
  viewerCanMinimize: {
    state: 'fulfilled',
    source: null,
    value: true,
  },
  minimizedReason: null,
  viewerCanDelete: true,
  viewerCanUpdate: true,
  viewerCanReport: true,
  viewerCanReportToMaintainer: false,
  viewerCanBlockFromOrg: false,
  viewerCanUnblockFromOrg: false,
  viewerDidAuthor: true,
  urlFragment: 'r2',
  viewerCanReadUserContentEdits: true,
  author: monalisa,
  authorAssociation: 'owner',
  threadId: 'app/helpers/react_helper.rb::4',
}

export const threadMarkers = {
  threadMarkers: [
    {
      path: 'app/helpers/react_helper.rb',
      position: 4,
      count: 1,
      threads: [
        {
          id: 'app/helpers/react_helper.rb::4',
          commentsData: {
            totalCount: 1,
            comments: [
              {
                id: 1,
                author: monalisa,
              },
            ],
          },
          diffSide: 'RIGHT',
        },
      ],
    },
  ],
  discussionComments: {
    comments: [],
    count: 0,
    canLoadMore: false,
  },
  subscribed: true,
  inlineComments: {
    'app/helpers/react_helper.rb': {
      '4': [
        {
          author: {
            id: '2',
            login: 'monalisa',
            avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
          },
          authorAssociation: 'member',
          body: 'asdgasdh',
          createdAt: '2025-01-27T15:12:14.000-08:00',
          // eslint-disable-next-line github/unescaped-html-literal
          htmlBody: '<p dir="auto">asdgasdh</p>',
          id: 16,
          isHidden: false,
          lastUserContentEdit: null,
          minimizedReason: null,
          path: 'symbol-search-directory/functools.py',
          position: 4,
          relayId: 'CC_kwASEA',
          threadId: 'symbol-search-directory/functools.py::11',
          updatedAt: '2025-01-27T15:12:14.000-08:00',
          urlFragment: 'r16',
          viewerCanBlockFromOrg: false,
          viewerCanDelete: true,
          viewerCanMinimize: true,
          viewerCanReadUserContentEdits: true,
          viewerCanReport: true,
          viewerCanReportToMaintainer: false,
          viewerCanUnblockFromOrg: false,
          viewerCanUpdate: true,
          viewerDidAuthor: true,
        },
        {
          author: {
            id: '2',
            login: 'monalisa',
            avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
          },
          authorAssociation: 'member',
          body: 'asdagasdhasdh',
          createdAt: '2025-01-27T15:12:35.000-08:00',
          // eslint-disable-next-line github/unescaped-html-literal
          htmlBody: '<p dir="auto">asdagasdhasdh</p>',
          id: 17,
          isHidden: false,
          lastUserContentEdit: null,
          minimizedReason: null,
          path: 'symbol-search-directory/functools.py',
          position: 4,
          relayId: 'CC_kwASEQ',
          threadId: 'symbol-search-directory/functools.py::11',
          updatedAt: '2025-01-27T15:12:35.000-08:00',
          urlFragment: 'r17',
          viewerCanBlockFromOrg: false,
          viewerCanDelete: true,
          viewerCanMinimize: true,
          viewerCanReadUserContentEdits: true,
          viewerCanReport: true,
          viewerCanReportToMaintainer: false,
          viewerCanUnblockFromOrg: false,
          viewerCanUpdate: true,
          viewerDidAuthor: true,
        },
      ],
    },
  },
}

export function gqlCommitCommentWithEditViewerHistory({relayId}: {relayId: string}) {
  return {
    data: {
      node: {
        id: relayId,
        lastEditedAt: null,
        lastUserContentEdit: null,
        viewerCanReadUserContentEdits: true,
        __isComment: 'CommitComment',
        __typename: 'CommitComment',
      },
    },
  }
}

export function gqlCommitCommentWithReactionGroups({relayId}: {relayId: string}) {
  return {
    data: {
      node: {
        id: relayId,
        __typename: 'CommitComment',
        __isComment: 'CommitComment',
        __isReactable: 'CommitComment',
        reactionGroups: [
          {
            content: 'THUMBS_UP',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'THUMBS_DOWN',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'LAUGH',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'HOORAY',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'CONFUSED',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'HEART',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'ROCKET',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
          {
            content: 'EYES',
            viewerHasReacted: false,
            reactors: {
              totalCount: 0,
              nodes: [],
            },
          },
        ],
      },
    },
  }
}

export const rootComponentDiffEntry = {
  diffLines: [
    {
      type: 'HUNK',
      blobLineNumber: 21,
      text: '@@ -22,7 +22,7 @@ class RootComponent < ApplicationComponent',
      html: '@@ -22,7 +22,7 @@ class RootComponent &lt; ApplicationComponent',
      position: 0,
      left: 21,
      right: 21,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 22,
      text: ' ',
      // eslint-disable-next-line github/unescaped-html-literal
      html: '<br>',
      position: 1,
      left: 22,
      right: 22,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 23,
      text: '       # The parent component for a file tree, which builds a tree representation',
      html: '       <span class=pl-c># The parent component for a file tree, which builds a tree representation</span>',
      position: 2,
      left: 23,
      right: 23,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 24,
      text: '       # of the given diff and renders a collection of child components, where',
      html: '       <span class=pl-c># of the given diff and renders a collection of child components, where</span>',
      position: 3,
      left: 24,
      right: 24,
    },
    {
      type: 'DELETION',
      blobLineNumber: 25,
      text: '-      # each child is a PullRequest::FileTree::NodeComponent.',
      html: '-      <span class="pl-c"># each child is a <span class="x x-first x-last">PullRequest</span>::FileTree::NodeComponent.</span>',
      position: 4,
      left: 25,
      right: 24,
    },
    {
      type: 'ADDITION',
      blobLineNumber: 25,
      text: '+      # each child is a PullRequests::FileTree::NodeComponent.',
      html: '+      <span class="pl-c"># each child is a <span class="x x-first x-last">PullRequests</span>::FileTree::NodeComponent.</span>',
      position: 5,
      left: 25,
      right: 25,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 26,
      text: '       #',
      html: '       <span class=pl-c>#</span>',
      position: 6,
      left: 26,
      right: 26,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 27,
      text: '       # diff - An instance of GitHub::Diff',
      html: '       <span class=pl-c># diff - An instance of GitHub::Diff</span>',
      position: 7,
      left: 27,
      right: 27,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 28,
      text: '       # viewed_files (optional) - An instance of PullRequestUserReviews',
      html: '       <span class=pl-c># viewed_files (optional) - An instance of PullRequestUserReviews</span>',
      position: 8,
      left: 28,
      right: 28,
    },
  ],
  diffNumber: 0,
  diffSize: '0 Bytes',
  isBinary: false,
  isTooBig: false,
  isSubmodule: false,
  linesChanged: 2,
  newTreeEntry: {
    path: 'app/components/pull_requests/file_tree/root_component.rb',
    mode: 100644,
    lineCount: 60,
    isGenerated: false,
  },
  oldTreeEntry: {
    path: 'app/components/pull_requests/file_tree/root_component.rb',
    mode: 100644,
    lineCount: 60,
  },
  linesAdded: 1,
  linesDeleted: 1,
  path: 'app/components/pull_requests/file_tree/root_component.rb',
  pathDigest: 'b380a745f19cffd4e405d0b2fbac10a2245703d66a901df274d0a41cb1b6839b',
  status: 'MODIFIED',
  truncatedReason: null,
  oldOid: '89c5109b75b889f2842d5692b8f3a260854e591d',
  newOid: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  copilotChatReference: undefined,
  deletedSha: '89c5109b75b889f2842d5692b8f3a260854e591d',
  canToggleRichDiff: false,
  defaultToRichDiff: false,
  proseDifffHtml: undefined,
  renderInfo: undefined,
  dependencyDiffPath: undefined,
} as DiffEntryDataWithExtraInfo

export const reactHelperDiffEntry = {
  collapsed: false,
  diffManuallyExpanded: false,
  objectId: 'objectId',
  diffLines: [
    {
      type: 'HUNK',
      blobLineNumber: 62,
      text: '@@ -63,7 +63,6 @@ module ClassMethods',
      html: '@@ -63,7 +63,6 @@ module ClassMethods',
      position: 0,
      left: 62,
      right: 62,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 63,
      text: '       app_name: T.nilable(String), # The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`',
      html: '       <span class=pl-pds>app_name</span>: <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>nilable</span><span class=pl-kos>(</span><span class=pl-v>String</span><span class=pl-kos>)</span><span class=pl-kos>,</span> <span class=pl-c># The react bundle name. If specified, it will be used instead of class-level `react_bundle_name`</span>',
      position: 1,
      left: 63,
      right: 63,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 64,
      text: '       origin: String, # The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow',
      html: '       <span class=pl-pds>origin</span>: <span class=pl-v>String</span><span class=pl-kos>,</span> <span class=pl-c># The origin of the request. Defaults to Platform::ORIGIN_API, override only if authorization happens in another place in the request flow</span>',
      position: 2,
      left: 64,
      right: 64,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 65,
      text: '       run_async_with_defer: T::Boolean, # Boolean defaulting to false signaling if the app should be rendered with the defer directive.',
      html: '       <span class=pl-pds>run_async_with_defer</span>: <span class=pl-c1>T</span>::<span class=pl-v>Boolean</span><span class=pl-kos>,</span> <span class=pl-c># Boolean defaulting to false signaling if the app should be rendered with the defer directive.</span>',
      position: 3,
      left: 65,
      right: 65,
    },
    {
      type: 'DELETION',
      blobLineNumber: 66,
      text: '-      enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally',
      html: '-      <span class=pl-pds>enabled_flags</span>: <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>nilable</span><span class=pl-kos>(</span><span class=pl-c1>T</span>::<span class=pl-v>Array</span><span class=pl-kos>[</span><span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>untyped</span><span class=pl-kos>]</span><span class=pl-kos>)</span><span class=pl-kos>,</span> <span class=pl-c># Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally</span>',
      position: 4,
      left: 66,
      right: 65,
      threadsData: {
        totalCommentsCount: 1,
        totalCount: 1,
        threads: [
          {
            id: 'app/helpers/react_helper.rb::4',
            diffSide: 'RIGHT',
            commentsData: {
              totalCount: 1,
              comments: [
                {
                  id: 1,
                  author: monalisa,
                },
              ],
            },
            line: 66,
            isOutdated: false,
          },
        ],
      },
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 66,
      text: '       add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String])))',
      html: '       <span class=pl-pds>add_query_time_tags_fn</span>: <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>nilable</span><span class=pl-kos>(</span><span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>proc</span><span class=pl-kos>.</span><span class=pl-en>params</span><span class=pl-kos>(</span><span class=pl-pds>arg0</span>: <span class=pl-v>String</span><span class=pl-kos>,</span> <span class=pl-pds>arg1</span>: <span class=pl-c1>T</span>::<span class=pl-v>Hash</span><span class=pl-kos>[</span><span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>untyped</span><span class=pl-kos>,</span> <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>untyped</span><span class=pl-kos>]</span><span class=pl-kos>)</span><span class=pl-kos>.</span><span class=pl-en>returns</span><span class=pl-kos>(</span><span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>nilable</span><span class=pl-kos>(</span><span class=pl-c1>T</span>::<span class=pl-v>Array</span><span class=pl-kos>[</span><span class=pl-v>String</span><span class=pl-kos>]</span><span class=pl-kos>)</span><span class=pl-kos>)</span><span class=pl-kos>)</span>',
      position: 5,
      left: 67,
      right: 66,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 67,
      text: '     ).returns(T.untyped)',
      html: '     <span class=pl-kos>)</span><span class=pl-kos>.</span><span class=pl-en>returns</span><span class=pl-kos>(</span><span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>untyped</span><span class=pl-kos>)</span>',
      position: 6,
      left: 68,
      right: 67,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 68,
      text: '   end',
      html: '   <span class=pl-k>end</span>',
      position: 7,
      left: 69,
      right: 68,
    },
    {
      type: 'HUNK',
      blobLineNumber: 85,
      text: '@@ -87,7 +86,6 @@ def render_react_app(',
      html: '@@ -87,7 +86,6 @@ def render_react_app(',
      position: 8,
      left: 86,
      right: 85,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 86,
      text: '     app_name: nil,',
      html: '     <span class=pl-s1>app_name</span>: <span class=pl-c1>nil</span><span class=pl-kos>,</span>',
      position: 9,
      left: 87,
      right: 86,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 87,
      text: '     origin: Platform::ORIGIN_API,',
      html: '     <span class=pl-s1>origin</span>: <span class=pl-v>Platform</span>::<span class=pl-c1>ORIGIN_API</span><span class=pl-kos>,</span>',
      position: 10,
      left: 88,
      right: 87,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 88,
      text: '     run_async_with_defer: false,',
      html: '     <span class=pl-s1>run_async_with_defer</span>: <span class=pl-c1>false</span><span class=pl-kos>,</span>',
      position: 11,
      left: 89,
      right: 88,
    },
    {
      type: 'DELETION',
      blobLineNumber: 90,
      text: '-    enabled_flags: [],',
      html: '-    <span class=pl-s1>enabled_flags</span>: <span class=pl-kos>[</span><span class=pl-kos>]</span><span class=pl-kos>,</span>',
      position: 12,
      left: 90,
      right: 88,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 89,
      text: '     add_query_time_tags_fn: nil',
      html: '     <span class=pl-s1>add_query_time_tags_fn</span>: <span class=pl-c1>nil</span>',
      position: 13,
      left: 91,
      right: 89,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 90,
      text: '   )',
      html: '   <span class=pl-kos>)</span>',
      position: 14,
      left: 92,
      right: 90,
    },
    {
      type: 'CONTEXT',
      blobLineNumber: 91,
      text: '     T.bind(self, T.untyped)',
      html: '     <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>bind</span><span class=pl-kos>(</span><span class=pl-smi>self</span><span class=pl-kos>,</span> <span class=pl-c1>T</span><span class=pl-kos>.</span><span class=pl-en>untyped</span><span class=pl-kos>)</span>',
      position: 15,
      left: 93,
      right: 91,
    },
  ],
  diffNumber: 0,
  diffSize: '0 Bytes',
  isBinary: false,
  isTooBig: false,
  isSubmodule: false,
  linesChanged: 13,
  newTreeEntry: {
    path: 'app/helpers/react_helper.rb',
    mode: 100644,
    lineCount: 91,
    isGenerated: false,
  },
  oldTreeEntry: {
    path: 'app/helpers/react_helper.rb',
    mode: 100644,
    lineCount: 93,
  },
  linesAdded: 2,
  linesDeleted: 11,
  path: 'app/helpers/react_helper.rb',
  pathDigest: '2095d5bfe192c31a5f3af38d7592bafc30cc9443a4c2f25034d6449ed5dcc0a6',
  status: 'MODIFIED',
  truncatedReason: null,
  oldOid: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  newOid: '3559d7dd01262de446758e90e902b4dd58565a2a',
  copilotChatReference: undefined,
  deletedSha: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  canToggleRichDiff: false,
  defaultToRichDiff: false,
  proseDifffHtml: undefined,
  renderInfo: undefined,
  dependencyDiffPath: undefined,
} as DiffEntryDataWithExtraInfo

const submoduleDiffEntry: DiffEntryDataWithExtraInfo = {
  diffNumber: 0,
  newTreeEntry: {
    path: 'illuminati',
    mode: 100644,
    lineCount: 1,
    isGenerated: false,
  },
  oldTreeEntry: {
    path: 'illuminati',
    mode: 100644,
    lineCount: 1,
  },
  collapsed: false,
  diffManuallyExpanded: false,
  isSubmodule: true,
  oldOid: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  newOid: '3559d7dd01262de446758e90e902b4dd58565a2a',
  diffSize: '',
  diffLines: [],
  isBinary: false,
  isTooBig: false,
  linesAdded: 0,
  linesDeleted: 0,
  linesChanged: 0,
  objectId: '',
  path: 'illuminati',
  pathDigest: 'path-illuminati',
  status: 'MODIFIED',
  truncatedReason: undefined,
  canToggleRichDiff: false,
  defaultToRichDiff: false,
  submodule: mockSubmodule,
}

export const monalisaSmileRepo = {
  id: 4,
  defaultBranch: 'main',
  name: 'smile',
  ownerLogin: 'monalisa',
  currentUserCanPush: false,
  isFork: false,
  isEmpty: false,
  createdAt: '2024-11-27T06:30:32.000-08:00',
  ownerAvatar: 'http://alambic.github.localhost/avatars/u/2',
  public: true,
  private: false,
  isOrgOwned: false,
}

export const payload: CommitPayload = {
  ...getCommitRoutePayload(),
  commit: {
    oid: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
    url: '/monalisa/smile/commit/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
    authoredDate: '2024-12-02T14:44:46.000-08:00',
    committedDate: '2024-12-02T14:44:46.000-08:00',
    // eslint-disable-next-line github/unescaped-html-literal
    shortMessageMarkdown: '<div>Update root_component.rb</div>' as SafeHTMLString,
    bodyMessageHtml: '' as SafeHTMLString,
    authors: [
      {
        login: 'monalisa',
        displayName: 'monalisa',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
        path: '/monalisa',
        isGitHub: false,
      },
    ],
    committerAttribution: false,
    committer: {
      login: 'web-flow',
      displayName: 'GitHub',
      avatarUrl: 'http://alambic.github.localhost/avatars/u/3',
      path: '/web-flow',
      isGitHub: true,
    },
    parents: ['89c5109b75b889f2842d5692b8f3a260854e591d'],
    globalRelayId: 'C_kwAE2gAoNDgyZWEyZjA2YTRiZjZmZjQwMjk1ZGI2OGFmZTJhMzNkMmQ5YTA4Yg',
    sha1: '89c5109b75b889f2842d5692b8f3a260854e591d',
    sha2: '482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  },
  currentUser: {
    id: 2,
    login: 'monalisa',
    userEmail: 'octocat@github.com',
    avatarURL: 'http://alambic.github.localhost/avatars/u/2',
    tabSize: 8,
  },
  repo: monalisaSmileRepo,
  diffEntryData: [rootComponentDiffEntry, reactHelperDiffEntry],
  splitViewPreference: 'unified',
  ignoreWhitespace: false,
  diffLineSpacingPreference: 'relaxed',
  useMonospaceFont: false,
  pasteUrlLinkAsPlainText: false,
  userNotices: [
    {
      name: 'compact_diff_lines',
      dismissed: true,
    },
  ],
  path: '/monalisa/smile/commit/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
  fileTreeExpanded: true,
  headerInfo: {
    additions: 1,
    deletions: 1,
    filesChanged: 1,
    filesChangedString: '1',
  },
  moreDiffsToLoad: false,
  asyncDiffLoadInfo: {
    startIndex: 1,
    truncated: false,
    byteCount: 476,
    lineShownCount: 9,
  },
  commentInfo: {
    canComment: true,
    locked: false,
    canLock: true,
    repoArchived: false,
  },
}

export const payloadWithSubmoduleDiff: CommitPayload = {
  ...payload,
  diffEntryData: [submoduleDiffEntry],
}

export const handlers = [
  http.get('monalisa/smile/commit/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b/deferred_comment_data', () =>
    HttpResponse.json(threadMarkers),
  ),

  http.get('monalisa/smile/commit/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b/deferred_commit_data', () =>
    HttpResponse.json(threadMarkers),
  ),

  http.get('/monalisa/smile/commit/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b/inline_comments', req => {
    const url = new URL(req.request.url, window.location.origin)
    const isRefetch = url.searchParams.get('isRefetch') === 'true'
    if (isRefetch) {
      return HttpResponse.json({
        comments: [...initialCommentsForReactHelperRb.comments, createdCommentForReactHelperRb],
      })
    }
    return HttpResponse.json(initialCommentsForReactHelperRb)
  }),

  http.get('/_graphql', req => {
    const url = new URL(req.request.url, window.location.origin)
    const params = JSON.parse(url.searchParams.get('body') ?? '{}')
    const ReactionViewerQueryId = 'd284cb78e50ac8ee8a082f7850e0f1de'

    if (params.query === ReactionViewerQueryId && params.variables.id === relayIdFirstCommentForReactHelperRb) {
      return HttpResponse.json(gqlCommitCommentWithReactionGroups({relayId: relayIdFirstCommentForReactHelperRb}))
    }

    // Fallback for all other queries
    return HttpResponse.json(gqlCommitCommentWithReactionGroups({relayId: relayIdFirstCommentForReactHelperRb}))
  }),

  http.post('/monalisa/smile/commit_comment/create', () => {
    return HttpResponse.json({comment: createdCommentForReactHelperRb})
  }),
]
