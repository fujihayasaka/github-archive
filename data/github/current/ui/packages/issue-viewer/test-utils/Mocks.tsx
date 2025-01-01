import type {MockResolverContext} from 'relay-test-utils/lib/RelayMockPayloadGenerator'
import type {Assignee, IssueMetadataFields, IssueType, Label, Milestone, Project} from './types'

export const DEFAULT_ASSIGNEES: Assignee[] = [
  {
    id: 'U_1',
    login: 'mona',
    name: 'Mona',
    avatarUrl: 'https://avatars.githubusercontent.com/mona?size=40',
    profileResourcePath: '/mona',
    __typename: 'User',
  },
  {
    id: 'U_2',
    login: 'hubot',
    name: 'Hugh Bot',
    avatarUrl: 'https://avatars.githubusercontent.com/hubot?size=40',
    profileResourcePath: '/apps/hubot',
    __typename: 'User',
  },
]

export const DEFAULT_LABELS: Label[] = [
  {
    color: '00A1F1',
    nameHTML: 'accessibility',
    description: 'An issue that impacts accessibility',
  },
  {
    color: '7CBB00',
    nameHTML: 'good first issue',
    description: 'Great for newcomers to pickup',
  },
  {
    color: 'FFBB00',
    nameHTML: 'Sev1',
    description: 'A severity 1 issue',
  },
  {
    color: 'F66314',
    nameHTML: 'bug',
    description: 'This issue is a bug in the code',
  },
]

export const DEFAULT_PROJECTS: Project[] = [
  {
    project: {
      title: 'Backlog',
    },
  },
]

export const DEFAULT_ISSUE_TYPE: IssueType = {
  id: 'IT_1',
  name: 'Bug',
  isEnabled: true,
  description: 'A bug report',
}

export const DEFAULT_MILESTONE: Milestone = {
  id: 'M_1',
  title: 'v1.0',
  closed: false,
  dueOn: '2022-01-01',
  progressPercentage: 0.5,
  url: '/milestone/1',
  closedAt: null,
}

export function makeIssueBaseFields() {
  return {
    DateTime() {
      return '2021-01-01T00:00:00Z'
    },
    String(context: MockResolverContext) {
      if (context.parentType === 'Issue' && context.name === 'title') {
        return 'Issue title'
      }
      if (context.parentType === 'Project' && context.name === 'name') {
        return 'project name'
      }
      if (context.name === 'color') {
        return 'ff0000'
      }
      if (context.name === 'createdAt') {
        return '2021-01-01T00:00:00Z'
      }
      if (context.name === 'enterpriseManagedEnterpriseId') {
        return null
      }
    },
    URI(context: MockResolverContext) {
      if (context.name === 'avatarUrl') {
        return 'https://avatars.githubusercontent.com/u/9919?v=4&size=48'
      }
    },
    HTML(context: MockResolverContext, generateId: () => number) {
      if (context.name === 'titleHTML') {
        return 'Issue title'
      }
      if (context.parentType === 'Issue' && context.name === 'bodyHTML') {
        return `Body ${generateId()}`
      }
      if (context.parentType === 'IssueComment' && context.name === 'bodyHTML') {
        return `comment body ${generateId()}`
      }
    },
    Int(context: MockResolverContext) {
      if (context.parentType === 'Issue' && context.name === 'number') {
        return 1234
      } else if (context.parentType === 'IssueTimelineItemsConnection' && context.name === 'totalCount') {
        return 0
      }
    },
  }
}

export const makeIssueMetadataFields = ({assignees, labels, projects, issueType, milestone}: IssueMetadataFields) => ({
  Issue: () => ({
    assignedActors: {
      nodes: assignees ?? [],
    },
    labels: {
      edges: labels ? labels.map(label => ({node: label})) : [],
    },
    projectItemsNext: {
      edges: projects ? projects.map(project => ({node: project})) : [],
    },
    issueType,
    milestone,
  }),
})
