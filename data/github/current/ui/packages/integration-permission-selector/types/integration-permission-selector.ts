export interface ResourcesSections {
  business: ResourcePermission[]
  organization: ResourcePermission[]
  repository: ResourcePermission[]
  user: ResourcePermission[]
}

export interface ResourcePermission {
  metadata: ResourcePermissionMetadata
  name: string
}

export interface ResourcePermissionMetadata {
  actions: ResourcePermissionActions
  description: string
  docs_url: string
  human_name: string
  resource_group: string
  title: string
}

export interface ResourcePermissionActions {
  admin: string
  none: string
  read: string
  write: string
}

export interface ViewContext {
  disabledForAllActions: boolean
  grantedPermissions: {[key: string]: string}
  integrationView: boolean
  resourceDocsUrl: string
}

export interface CurrentTargetFields {
  id: number
  login: string
  type: string
}

export interface SectionsShown {
  enterprise: boolean
  organization: boolean
  repository: boolean
  user: boolean
}
