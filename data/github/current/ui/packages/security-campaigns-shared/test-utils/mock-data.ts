import type {Repository} from '../types/repository'
import type {DraftSecurityCampaign, SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'
import type {User} from '../types/user'
import type {Team} from '../types/team'

export function getUser(data?: Partial<User>): User {
  return {
    id: 2,
    login: 'monalisa',
    name: 'Mona Lisa',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
    ...data,
  }
}

export function getTeam(data?: Partial<Team>): Team {
  return {
    id: 1,
    name: 'Team',
    slug: 'team',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
    organizationLogin: 'testOrg',
    ...data,
  }
}

export function getSecurityCampaign(data?: Partial<SecurityCampaign>): SecurityCampaign {
  return {
    id: 17,
    number: 5,
    name: 'User-controlled code injection',
    description:
      'Directly evaluating user input (for example, an HTTP request parameter) as code without first sanitizing the input allows an attacker arbitrary code execution.',
    endsAt: '2024-05-12T00:00:00.000Z',
    closedAt: null,
    managers: [getUser()],
    teamManagers: [],
    contactLink: 'https://www.example.test',
    createdAt: '2024-05-01T00:00:00.000Z',
    creationQuery: null,
    publishedAt: '2024-05-01T00:00:00.000Z',
    ...data,
  }
}

export function getDraftSecurityCampaign(data?: Partial<DraftSecurityCampaign>): DraftSecurityCampaign {
  return {
    ...getSecurityCampaign(),
    creationQuery: 'is:open',
    endsAt: null,
    publishedAt: null,
    ...data,
  }
}

export function getSecurityCampaignWithCounts(data?: Partial<SecurityCampaignWithCounts>): SecurityCampaignWithCounts {
  return {
    ...getSecurityCampaign(),
    openCount: 10,
    closedCount: 5,
    openWithLinksCount: 2,
    ...data,
  }
}

export function createRepository(data?: Partial<Repository>): Repository {
  return {
    ownerLogin: 'github',
    name: 'security-campaigns',
    typeIcon: 'lock',
    ...data,
  }
}
