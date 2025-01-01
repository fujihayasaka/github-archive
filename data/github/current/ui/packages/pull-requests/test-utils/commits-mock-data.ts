import {createRepository} from '@github-ui/current-repository/test-helpers'
import {generateCommitGroups} from '@github-ui/commits/test-helpers'
import type {CommitsRoutePayload} from '../routes/Commits'
import {getHeaderPageData} from './header-mock-data'

export function getCommitsPageData() {
  return {
    commitGroups: generateCommitGroups(1, 1),
    metadata: {
      deferredCommitsDataUrl: '/monalisa/smile/pull/1/deferred_commits_data',
    },
    repository: createRepository(),
    timeOutMessage: '',
    truncated: false,
  }
}

export function getCommitsRoutePayload(): CommitsRoutePayload {
  return {...getCommitsPageData(), ...getHeaderPageData()}
}
