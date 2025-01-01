import type {ParentIssue} from '../../client/api/common-contracts'

export const mockParentIssues = new Array<ParentIssue>(
  {
    id: 1,
    globalRelayId: 'I_kwARTg',
    number: 10,
    title: 'Parent One',
    titleHtml: 'Parent One',
    state: 'open',
    nwoReference: 'github/sriracha-4#10',
    url: 'http://github.localhost:80/github/sriracha-4/issues/14',
    owner: 'github',
    repository: 'sriracha-4',
    subIssueList: {
      total: 1,
      completed: 0,
      percentCompleted: 0,
    },
    updatedAt: '2024-10-30T00:00:00Z',
  },
  {
    id: 2,
    globalRelayId: 'I_kwARSw',
    number: 11,
    title: 'Parent Two',
    titleHtml: 'Parent Two',
    state: 'closed',
    stateReason: 'completed',
    nwoReference: 'github/sriracha-4#11',
    url: 'http://github.localhost:80/github/sriracha-4/issues/15',
    owner: 'github',
    repository: 'sriracha-4',
    subIssueList: {
      total: 1,
      completed: 0,
      percentCompleted: 0,
    },
    updatedAt: '2024-10-29T00:00:00Z',
  },
  {
    id: 3,
    globalRelayId: 'I_kwARS2',
    number: 12,
    title: 'Parent Three',
    titleHtml: 'Parent Three',
    state: 'closed',
    stateReason: 'not_planned',
    nwoReference: 'github/sriracha-4#12',
    url: 'http://github.localhost:80/github/sriracha-4/issues/16',
    owner: 'github',
    repository: 'sriracha-4',
    subIssueList: {
      total: 1,
      completed: 0,
      percentCompleted: 0,
    },
    updatedAt: '2024-10-15T00:00:00Z',
  },
)

export function getParentIssue(id: number): ParentIssue {
  const parentIssue = mockParentIssues.find(issue => issue.id === id)
  if (!parentIssue) {
    throw Error(`Unable to find parent issue with id ${id} - please check the mock data`)
  }
  return parentIssue
}
