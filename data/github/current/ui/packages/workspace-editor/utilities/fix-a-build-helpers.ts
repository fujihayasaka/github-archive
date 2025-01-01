import type {CopilotChatReference, PullRequestReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {Repository} from '@github-ui/current-repository'
import type {RefInfo} from '@github-ui/repos-types'

import type {PullRequestData} from './workspace-editor-types'

export const USER_MESSAGE =
  'Analyze the failure in the terminal output, explain why the failure occurred, and suggest a fix.'

export function formatTerminalOutputAsReference(
  output: string,
  repo: Repository,
  pullRequestID: string,
): CopilotChatReference {
  return {
    type: 'workspace-terminal-log',
    output,
    pullRequestID,
    repoID: repo.id,
    repoOwner: repo.ownerLogin,
    repoName: repo.name,
  }
}

export function formatChangedFilesAsReference(changedFiles: Array<{path: string}>): CopilotChatReference {
  return {
    displayName: 'List of changed files',
    displayIcon: '',
    displayUrl: '',
    type: 'third-party',
    thirdPartyType: 'workspace-changed-files',
    data: changedFiles.map(f => `- ${f.path}`).join('\n'),
  }
}

export function formatPullRequestAsReference(
  pullRequest: PullRequestData,
  repository: Repository,
  refInfo: RefInfo,
): PullRequestReference {
  return {
    type: 'pull-request',
    title: pullRequest.title,
    url: `/${repository.ownerLogin}/${repository.name}/pull/${pullRequest.number}`,
    commit: pullRequest.headSHA,
    authorLogin: pullRequest.authorLogin,
    repository: {
      ...repository,
      ownerType: repository.isOrgOwned ? 'Organization' : 'User',
      commitOID: pullRequest.headSHA,
      ref: refInfo.name,
      refInfo: {
        name: refInfo.name,
        type: refInfo.refType || 'branch',
      },
      visibility: repository.public ? 'PUBLIC' : 'PRIVATE',
    },
  }
}
