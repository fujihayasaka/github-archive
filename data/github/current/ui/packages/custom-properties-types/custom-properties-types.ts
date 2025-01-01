import type {ListResults} from '@github-ui/repos-list-shared'

export type PropertyValue = string | string[]
export const BOOLEAN_PROPERTY_ALLOWED_VALUES = ['true', 'false']
export type PropertyValuesRecord = Record<string, PropertyValue>

export type OrgEditPermissions = 'all' | 'definitions' | 'values'
export type PropertyValidationErrors = Record<string, string>
export type ValueType = 'string' | 'single_select' | 'multi_select' | 'true_false'
export type ValuesEditableBy = 'org_and_repo_actors' | 'org_actors'

export type SourceType = 'org' | 'business'

export interface PropertyDefinition {
  propertyName: string
  valueType: ValueType
  required: boolean
  defaultValue: PropertyValue | null
  description: string | null
  allowedValues: string[] | null
  valuesEditableBy: ValuesEditableBy
  regex: string | null
  source: PropertySourceDetails
}

export interface PropertySourceDetails extends SourceInfo {
  type: SourceType
  avatarUrl: string
}

interface DefinitionsListResults {
  definitions: PropertyDefinition[]
  pageCount: number
  totalCount: number
}

export interface BusinessCustomPropertiesDefinitionsPagePayload extends DefinitionsListResults {
  ownDefinitionsCount: number
  currentQ: string
}

export interface OrgCustomPropertiesListPagePayload extends DefinitionsListResults {
  ownDefinitionsCount: number
  permissions: OrgEditPermissions
  activeTab: 'properties'
}

export interface OrgCustomPropertiesSetValuesPagePayload extends ListResults<Repository> {
  ownDefinitionsCount: number
  definitions: PropertyDefinition[]
  permissions: OrgEditPermissions
  activeTab: 'set-values'
  business?: SourceInfo
}

export type OrgCustomPropertiesPagePayload =
  | OrgCustomPropertiesListPagePayload
  | OrgCustomPropertiesSetValuesPagePayload

export type PropertiesPageTabName = OrgCustomPropertiesPagePayload['activeTab']

export interface SourceInfo {
  name: string
  slug: string
}

export interface RepoPropertiesPagePayload {
  definitions: PropertyDefinition[]
  values: PropertyValuesRecord
  canEditProperties: boolean
}

export interface RepoSettingsPropertiesPagePayload {
  definitions: PropertyDefinition[]
  currentRepo: Repository
  editableProperties: string[]
}

export interface CustomPropertyDetailsPagePayload {
  definition?: PropertyDefinition
  propertyNames: string[]
  business?: SourceInfo
  canManageProperty: boolean
  orgConflicts?: PropertyNameOrgConflicts
}

export interface CheckPropertyUsagesResponse {
  repositoriesCount: number
}

export interface Repository {
  id: number
  name: string
  visibility: 'public' | 'private' | 'internal'
  description: string | null
  properties?: PropertyValuesRecord
}

export interface PropertyNameValidationResult {
  message: string
  orgConflicts?: PropertyNameOrgConflicts
}

export interface PropertyNameOrgConflicts {
  usages: OrgConflictUsage[]
  totalUsageCount: number
}

export interface OrgConflictUsage {
  name: string
  avatarUrl: string
  propertyType: ValueType
}
