import type {
  CustomPropertyDetailsPagePayload,
  OrgCustomPropertiesListPagePayload,
  PropertyDefinition,
  RepoPropertiesPagePayload,
  RepoSettingsPropertiesPagePayload,
  Repository,
} from '@github-ui/custom-properties-types'

export const albumDefinition: PropertyDefinition = {
  propertyName: 'album',
  valueType: 'string',
  required: false,
  defaultValue: null,
  description: null,
  allowedValues: null,
  valuesEditableBy: 'org_actors',
  regex: null,
  sourceType: 'org',
}

export function getSchemaPagePayload(): OrgCustomPropertiesListPagePayload {
  return {
    activeTab: 'properties',
    ownDefinitionsCount: 1,
    definitions: [albumDefinition],
    totalCount: 1,
    pageCount: 1,
    permissions: 'all',
  }
}

export function getPropertyDetailsPagePayload(): CustomPropertyDetailsPagePayload {
  return {
    propertyNames: [albumDefinition.propertyName],
    canManageBusiness: false,
  }
}

export function getRepoCustomPropertiesPagePayload(): RepoPropertiesPagePayload {
  return {
    definitions: [albumDefinition],
    values: {
      album: 'Parachutes',
    },
    canEditProperties: false,
  }
}

export function getRepoSettingsCustomPropertiesPagePayload(): RepoSettingsPropertiesPagePayload {
  return {
    definitions: [albumDefinition],
    editableProperties: [],
    currentRepo: {
      id: 1,
      name: 'github',
      visibility: 'public',
      description: 'A great repo',
      properties: {
        album: 'Parachutes',
      },
    },
  }
}

export const sampleStorybookDefinitions: PropertyDefinition[] = [
  {
    propertyName: 'contains_phi',
    valueType: 'true_false',
    required: true,
    defaultValue: 'false',
    description: 'Is this repository used to process Protected Health Data under HIPAA?',
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'optional_bool',
    valueType: 'true_false',
    required: false,
    defaultValue: null,
    description: 'yes no, maybe?',
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'data_sensitivity',
    valueType: 'single_select',
    required: true,
    defaultValue: 'high',
    description:
      'Level of sensitivity of data processed by this repository once deployed. Refer to our data classification policy for details on determining classification levels.',
    allowedValues: ['low', 'medium', 'high'],
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'notes',
    valueType: 'string',
    required: true,
    defaultValue: 'foo',
    description: 'Enter some notes if you want',
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'cost_center_id',
    valueType: 'string',
    required: false,
    defaultValue: null,
    description: 'The department to which costs may be charged for accounting purposes.',
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'platform',
    valueType: 'multi_select',
    required: false,
    defaultValue: null,
    description: null,
    allowedValues: ['android', 'ios', 'web'],
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
  {
    propertyName: 'very_long_property_name_that_should_break_the_layout',
    valueType: 'string',
    required: false,
    defaultValue: null,
    description:
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse scelerisque velit id ex bibendum volutpat. ',
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    sourceType: 'org',
  },
]

export const sampleRepos: Repository[] = [
  {
    id: 0,
    name: 'maximum-effort',
    visibility: 'private',
    description: 'a test description',
    properties: {
      environment: 'prod',
    },
  },
  {
    id: 1,
    name: 'holly',
    visibility: 'internal',
    description: null,
    properties: {
      type: 'best',
      animal: 'dog',
    },
  },
  {
    id: 2,
    name: 'testing',
    visibility: 'public',
    description: null,
    properties: {
      environment: 'dev',
    },
  },
]
