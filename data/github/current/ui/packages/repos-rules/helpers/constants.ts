import type {RulesetTarget, TargetObjectType} from '../types/rules-types'

export const PUSH_RULESET_TARGET_INFO =
  'Push rulesets only apply to non-fork private or internal repositories and forks of those repositories.'

export const PLURAL_RULESET_TARGETS: {[key in RulesetTarget]: string} = {
  branch: 'branches',
  tag: 'tags',
  push: 'pushes',
  repository: 'repositories',
}

export const PLURAL_TARGET_OBJECT_TYPES: {[key in TargetObjectType]: string} = {
  ref: 'refs',
  repository: 'repositories',
  organization: 'organizations',
}

export const EXAMPLE_CONDITION_TARGET_PATTERNS: {
  [targetType: string]:
    | {
        [rulesetTarget: string]: string[]
      }
    | undefined
} = {
  ref_name: {
    branch: ['main', 'releases/**/*', 'users/**/*'],
    tag: ['*-beta', 'releases/**/*', 'v*'],
  },
  repository_name: {
    branch: ['prod-*', 'test-*'],
    tag: ['prod-*', 'test-*'],
  },
}

export const TEST_IDS = {
  metadataRulePanelSpan: 'metadata-span',
}

export const TARGET_OBJECT_BY_TYPE = {
  repository_name: 'repository',
  repository_id: 'repository',
  repository_property: 'repository',
  ref_name: 'ref',
  organization_name: 'organization',
  organization_id: 'organization',
}
export const TARGET_OBJECT_TYPES: TargetObjectType[] = ['organization', 'repository', 'ref']

export const UNKNOWN_REF_NAME = 'refs/__gh__/UNKNOWN'
export const PENDING_OID = 'PENDING'

export const INHERITED_SOURCE_TYPE_ORDER_MAP = {
  Enterprise: 0,
  Organization: 1,
  Upstream: 2,
  Repository: 3,
}

export const IMPORT_LOCAL_STORAGE_KEY = 'repos-rules/imported-ruleset'

export const STATIC_BYPASS_ACTOR_TYPES = ['DeployKey', 'OrganizationAdmin']
