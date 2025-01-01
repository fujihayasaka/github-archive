export const CostCenterState = {
  Active: 'CostCenterActive',
  Archived: 'CostCenterArchived',
} as const

export type CostCenterState = (typeof CostCenterState)[keyof typeof CostCenterState]

export const CostCenterType = {
  NoCostCenter: 'NoCostCenter',
  GitHubEnterpriseCustomer: 'GitHubEnterpriseCustomer',
  ZuoraSubscription: 'ZuoraSubscription',
  CreditCard: 'CreditCard',
  AzureSubscription: 'AzureSubscription',
} as const

export type CostCenterType = (typeof CostCenterType)[keyof typeof CostCenterType]

export const ResourceType = {
  NoTarget: 'NoTarget',
  User: 'User',
  Team: 'Team',
  Repo: 'Repo',
  Org: 'Org',
  Enterprise: 'Enterprise',
  CostCenterResource: 'CostCenterResource',
} as const

export type ResourceType = (typeof ResourceType)[keyof typeof ResourceType]
