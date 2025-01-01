import type {SafeHTMLString} from '@github-ui/safe-html'
import type {PullRequestState} from './components/PullRequestStateLabel'
import type {Subject} from '@github-ui/conversations'

export interface PullRequest {
  author: {
    login: string
  }
  baseBranch: string
  pathName: string
  commitsCount: number
  headBranch: string
  headRepositoryName?: string
  headRepositoryOwnerLogin?: string
  isInAdvisoryRepo: boolean
  mergedBy?: string
  mergedTime?: string
  number: number
  state: PullRequestState
  title: string
  titleHtml: SafeHTMLString
  url: string
  globalRelayId: string
  subject?: Subject | undefined
}
