import {useMemo} from 'react'
import type {Decorator} from '@storybook/react'

import {Wrapper} from '@github-ui/react-core/test-utils'
import type {WorkbenchRoutePayload} from '../../types/workbench-types'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export const withRoutePayload: Decorator = (Story, {args}) => {
  const contextValue = useMemo(() => ({
    deploymentVisibility: 'only_owner',
    workbench: {
      id: args.workbenchId as string,
      name: args.workbenchName as string,
      files: {},
      previousRefinements: [],
      title: args.workbenchTitle as string,
      description: args.workbenchDescription as string,
      suggestions: [],
      runtimePermanentName: args.workbenchRuntimePermanentName as string,
      friendlyName: args.workbenchFriendlyName as string,
      shouldGenerateInitialPrompt: true,
      updatedAt: '2023-01-01T00:00:00Z',
      deployUrl: args.workbenchDeployUrl as string,
      favorite: args.workbenchFavorite as boolean,
      currentRefinementId: 1,
      repositoryUrl: 'https://workbench.repositoryUrl.com',
      billableOwner: {
        id: 1,
        login: 'owner',
        type: 'User',
      },
      cloudspace_id: 'cloudspace-id',
    },
    friendlyName: args.routeFriendlyName as string,
    login: args.routeLogin as string,
    deploy: args.deployExists
      ? {
          createdAt: args.deployCreatedAt as string,
          deployLogin: args.deployLogin as string,
          displayName: args.deployDisplayName as string,
          domainBase: args.deployDomainBase as string,
        }
      : undefined,
    acaJwtInfo: {
      appName: '',
      payload: '',
      proxyPayload: '',
      userLogin: '',
    },
    previewDeploy: {
      createdAt: '',
      deployLogin: '',
      displayName: '',
      domainBase: '',
    },
    copilot: {
      apiURL: 'https://copilot.api.url',
      ssoOrganizations: [],
      currentTopic: {
        id: 0,
        name: '',
        ownerLogin: '',
        ownerType: 'User',
        readmePath: undefined,
        description: undefined,
        commitOID: '',
        ref: '',
        refInfo: {
          name: '',
          type: 'branch'
        },
        visibility: '',
        languages: undefined,
        customInstructions: undefined,
        path: undefined
      },
      agentsPath: '',
      currentUserLogin: '',
      optedInToPreviewFeatures: false,
      optedInToUserFeedback: false,
      reviewLab: false,
      licenseType: CopilotLicenseType.Unlicensed
    },
    path: 'file.txt',
    editorSettings: {
      codeLineWrapEnabled: true,
      whitespaceHidden: true,
      problemsHidden: true,
    },
  } satisfies Partial<WorkbenchRoutePayload>), [args.workbenchId,
    args.workbenchName,
    args.workbenchTitle,
    args.workbenchDescription,
    args.workbenchRuntimePermanentName,
    args.workbenchFriendlyName,
    args.workbenchDeployUrl,
    args.workbenchFavorite,
    args.routeFriendlyName,
    args.routeLogin,
    args.deployExists,
    args.deployCreatedAt,
    args.deployLogin,
    args.deployDisplayName,
    args.deployDomainBase,
  ])

  return (
    <Wrapper routePayload={contextValue}>
      <Story />
    </Wrapper>
  )
}

export const RoutePayloadDecoratorArgTypes = {
  workbenchId: {
    control: 'text',
    description: 'workbench.id',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchName: {
    control: 'text',
    description: 'workbench.name',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchTitle: {
    control: 'text',
    description: 'workbench.title',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchDescription: {
    control: 'text',
    description: 'workbench.description',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchRuntimePermanentName: {
    control: 'text',
    description: 'workbench.runtimePermanentName',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchFriendlyName: {
    control: 'text',
    description: 'workbench.friendlyName',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchDeployUrl: {
    control: 'text',
    description: 'workbench.deployUrl',
    table: {
      category: 'RoutePayload',
    },
  },
  workbenchFavorite: {
    control: 'boolean',
    description: 'workbench.favorite',
    table: {
      category: 'RoutePayload',
    },
  },
  routeFriendlyName: {
    control: 'text',
    description: 'route.friendlyName',
    table: {
      category: 'RoutePayload',
    },
  },
  routeLogin: {
    control: 'text',
    description: 'route.login',
    table: {
      category: 'RoutePayload',
    },
  },
  deployCreatedAt: {
    control: 'date',
    description: 'deploy.createdAt',
    table: {
      category: 'RoutePayload',
    },
  },
  deployLogin: {
    control: 'text',
    description: 'deploy.deployLogin',
    table: {
      category: 'RoutePayload',
    },
  },
  deployDisplayName: {
    control: 'text',
    description: 'deploy.displayName',
    table: {
      category: 'RoutePayload',
    },
  },
  deployDomainBase: {
    control: 'text',
    description: 'deploy.domainBase',
    table: {
      category: 'RoutePayload',
    },
  },
  deployExists: {
    control: 'boolean',
    description: 'Whether the deploy exists or not',
    table: {
      category: 'RoutePayload',
    },
  },
}

export const RoutePayloadDecoratorArgs = {
  workbenchId: '12345',
  workbenchName: 'My Workbench',
  workbenchTitle: 'My Workbench Title',
  workbenchDescription: 'My Workbench Description',
  workbenchRuntimePermanentName: 'my-runtime',
  workbenchFriendlyName: 'workbench-friendlyName',
  workbenchDeployUrl: 'https://workbench.DeployUrl.com',
  workbenchFavorite: false,
  routeFriendlyName: 'friendly-name',
  routeLogin: 'monalisa',
  deployCreatedAt: '2023-01-01T00:00:00Z',
  deployLogin: 'deploy-login',
  deployDisplayName: 'Deploy Display Name',
  deployDomainBase: 'deploy.domain.base',
  deployExists: true,
}
