import type {IntegrationPermissionSelectorProps} from '../../IntegrationPermissionSelector'

export function getIntegrationPermissionSelectorProps(): IntegrationPermissionSelectorProps {
  return {
    exampleMessage: 'example props for integration-permission-selector partial',
    resources: {
      repository: [
        {
          name: 'resource-repo',
          metadata: {
            actions: {
              admin: 'Admin',
              none: 'No access',
              read: 'Read-only',
              write: 'Read and write',
            },
            title: 'Resource Repo',
            description: 'Resource description.',
            docs_url: 'https://docs.github.com',
            human_name: 'Resource Repo',
            resource_group: '#organization-resource-repo',
          },
        },
      ],
      organization: [
        {
          name: 'resource-org',
          metadata: {
            actions: {
              admin: 'Admin',
              none: 'No access',
              read: 'Read-only',
              write: 'Read and write',
            },
            title: 'Resource Organization',
            description: 'Resource description.',
            docs_url: 'https://docs.github.com',
            human_name: 'Resource Organization',
            resource_group: '#organization-resource-org',
          },
        },
      ],
      user: [
        {
          name: 'resource-user',
          metadata: {
            actions: {
              admin: 'Admin',
              none: 'No access',
              read: 'Read-only',
              write: 'Read and write',
            },
            title: 'Resource User',
            description: 'Resource description.',
            docs_url: 'https://docs.github.com',
            human_name: 'Resource User',
            resource_group: '#organization-resource-user',
          },
        },
      ],
      business: [
        {
          name: 'resource-ent',
          metadata: {
            actions: {
              admin: 'Admin',
              none: 'No access',
              read: 'Read-only',
              write: 'Read and write',
            },
            title: 'Resource Enterprise',
            description: 'Resource description.',
            docs_url: 'https://docs.github.com',
            human_name: 'resource-ent',
            resource_group: '#organization-resource-ent',
          },
        },
      ],
    },
    view: {
      disabledForAllActions: false,
      grantedPermissions: {},
      integrationView: true,
      resourceDocsUrl: 'https://docs.github.com/en/rest/reference/apps#permissions-for-github-apps',
    },
    currentTarget: {
      type: 'user',
      id: '1234556',
      login: 'github',
    },
    showSections: {
      enterprise: true,
      organization: true,
      repository: true,
      user: true,
    },
  }
}
