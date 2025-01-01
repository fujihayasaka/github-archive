import type {Repository} from '../types/repository'
import type {SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'
import type {User} from '../types/user'

export function getUser(data?: Partial<User>): User {
  return {
    id: 2,
    login: 'monalisa',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
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
    manager: getUser(),
    createdAt: '2024-05-01T00:00:00.000Z',
    showPath: '/orgs/github/security/campaigns/1',
    updatePath: '/orgs/github/security/campaigns/1',
    deletePath: '/orgs/github/security/campaigns/1',
    closePath: '/orgs/github/security/campaigns/1/close',
    reopenPath: '/orgs/github/security/campaigns/1/reopen',
    ...data,
  }
}

export function getSecurityCampaignWithCounts(): SecurityCampaignWithCounts {
  return {
    ...getSecurityCampaign(),
    openCount: 10,
    closedCount: 5,
    openWithLinksCount: 2,
  }
}

export function createRepository(data?: Partial<Repository>): Repository {
  return {
    ownerLogin: 'github',
    name: 'security-campaigns',
    path: 'github/security-campaigns',
    typeIcon: 'lock',
    ...data,
  }
}
