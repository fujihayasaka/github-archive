import type {CopilotDetailsProps} from '../CopilotDetails'
import type {License, Organization, User} from '../types'

export function getCopilotDetailsProps(): CopilotDetailsProps {
  return {
    copilotDetails,
    enterpriseContactUrl: '',
    slug: 'github',
    isStafftools: false,
    isTeams: false,
    organizations: {
      withCopilotAccess: organizationsWithCopilotAccess,
      withoutCopilotAccess: organizationsWithoutCopilotAccess,
    },
    users: {
      withCopilotAccess: usersWithCopilotAccess,
    },
    isCopilotUserFlagEnabled: true,
    isCopilotEnterpriseTeamsFlagEnabled: true,
  }
}

export const skus = [
  {
    sku: 'business',
    unitPrice: 19,
    consumedLicenses: 3,
  },
  {
    sku: 'enterprise',
    unitPrice: 39,
    consumedLicenses: 5,
  },
]

const copilotDetails = {
  skus,
  billingTermEndDate: 'January, 20 2025',
  totalCost: 252,
  enablementSetting: 'selected_organizations',
  enabledOrganizationCount: 6,
  enabledUserCount: 10,
}

export const userLicenses: License[] = [
  {
    ownerType: 'organization',
    ownerName: 'org',
    ownerId: 15,
    expirationDate: null,
    planType: 'enterprise',
  },
  {
    ownerType: 'business',
    ownerName: 'ea',
    ownerId: 11,
    expirationDate: null,
    planType: 'business',
  },
]

export const organizationsWithCopilotAccess: Organization[] = [
  {
    login: 'github-1',
    id: 1,
    licenseCount: 5,
    copilotPlan: 'business',
    newPlan: 'business',
    copilotCanBeReenabled: false,
    expirationDate: '2026-12-01',
    orgUrl: '/organizations/org1',
    avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
  },
  {
    login: 'github-2',
    id: 2,
    licenseCount: 10,
    copilotPlan: 'enterprise',
    newPlan: 'enterprise',
    copilotCanBeReenabled: false,
    expirationDate: null,
    orgUrl: '/organizations/org2',
    avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  },
  {
    login: 'github-3',
    id: 13,
    licenseCount: 5,
    copilotPlan: 'disabled',
    newPlan: 'disabled',
    copilotCanBeReenabled: true,
    expirationDate: null,
    orgUrl: '/organizations/org3',
    avatarUrl: 'https://avatars.githubusercontent.com/u/3?v=4',
  },
]

export const usersWithCopilotAccess: User[] = [
  {
    login: 'github-1',
    name: 'mona',
    id: 25,
    userUrl: '/users/mona',
    avatarUrl: 'https://avatars.githubusercontent.com/u/mona?v=4',
    licenses: userLicenses,
    dominantLicense: userLicenses[0] ?? null,
  },
  {
    login: 'github-2',
    name: 'mona2',
    id: 29,
    userUrl: '/users/mona2',
    avatarUrl: 'https://avatars.githubusercontent.com/u/mona2?v=4',
    licenses: userLicenses,
    dominantLicense: userLicenses[0] ?? null,
  },
]

export const organizationsWithoutCopilotAccess: Organization[] = [
  {
    login: 'github-4',
    id: 14,
    licenseCount: 5,
    copilotPlan: 'disabled',
    newPlan: 'disabled',
    copilotCanBeReenabled: false,
    expirationDate: null,
    orgUrl: '/organizations/org4',
    avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
  },
  {
    login: 'github-5',
    id: 15,
    licenseCount: 10,
    copilotPlan: 'disabled',
    newPlan: 'disabled',
    copilotCanBeReenabled: false,
    expirationDate: null,
    orgUrl: '/organizations/org5',
    avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  },
  {
    login: 'github-6',
    id: 16,
    licenseCount: 10,
    copilotPlan: 'disabled',
    newPlan: 'disabled',
    copilotCanBeReenabled: false,
    expirationDate: null,
    orgUrl: '/organizations/org6',
    avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  },
]

export const usersWithoutCopilotAccess: User[] = [
  {
    login: 'github-3',
    name: 'mona3',
    id: 32,
    userUrl: '/users/mona3',
    avatarUrl: 'https://avatars.githubusercontent.com/u/mona3?v=4',
    licenses: [],
    dominantLicense: null,
  },
  {
    login: 'github-4',
    name: 'mona4',
    id: 33,
    userUrl: '/users/mona4',
    avatarUrl: 'https://avatars.githubusercontent.com/u/mona4?v=4',
    licenses: [],
    dominantLicense: null,
  },
]
