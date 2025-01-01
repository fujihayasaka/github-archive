import {action} from '@storybook/addon-actions'
import type {Args, ArgTypes, Decorator} from '@storybook/react'
import {
  initialState,
  WorkbenchStoreContext,
  Status,
  AgentStatus,
  CodespaceStatus,
  AcaStatus,
  CopilotPlan,
  CopilotLicenseType,
} from '../WorkbenchStoreContext'

export const workbenchStoreContextDecoratorArgs: Args = {
  workbenchReadOnly: false,
  hasServiceErrors: false,
  // status
  codespaceStatus: CodespaceStatus.CONNECTED,
  viteStatus: Status.CONNECTED,
  agentStatus: AgentStatus.CONNECTED,
  fileSyncerStatus: Status.CONNECTED,
  designerStatus: Status.CONNECTED,
  acaStatus: AcaStatus.RESOURCES_CREATED,
  copilotStatus: Status.CONNECTED,
  runtimeStatus: Status.CONNECTED,
  // entitlement
  copilotPlan: CopilotPlan.IndividualPro,
  copilotLicenseType: CopilotLicenseType.LicensedLimited,
  copilotChatQuota: 'under',
  copilotPremiumInteractionsQuota: 'under',
  copilotOveragesEnabled: true,
  codespaceComputeAllowed: true,
  codespaceComputeHoursQuota: 'under',
  codespaceSessionsAllowed: true,
}

export const workbenchStoreContextDecoratorArgTypes: ArgTypes = {
  setReadOnly: {table: {disable: true}},
  onError: {table: {disable: true}},
  onConnected: {table: {disable: true}},
  onDisconnected: {table: {disable: true}},
  onIdle: {table: {disable: true}},
  onStatus: {table: {disable: true}},
  onCodespaceStatus: {table: {disable: true}},
  onSuccess: {table: {disable: true}},
  workbenchReadOnly: {
    control: 'boolean',
    description: 'Are we in the read-only state?',
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.workbenchReadOnly.toString()},
      category: 'WorkbenchStoreContext',
    },
  },
  hasServiceErrors: {
    control: 'boolean',
    description: 'Representing whether any service is in an error state, computed from status in production',
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.hasServiceErrors.toString()},
      category: 'WorkbenchStoreContext',
    },
  },
  // Status
  codespaceStatus: {
    control: 'select',
    options: Object.values(CodespaceStatus),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.codespaceStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  viteStatus: {
    control: 'select',
    options: Object.values(Status),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.viteStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  agentStatus: {
    control: 'select',
    options: Object.values(AgentStatus),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.agentStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  fileSyncerStatus: {
    control: 'select',
    options: Object.values(Status),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.fileSyncerStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  designerStatus: {
    control: 'select',
    options: Object.values(Status),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.designerStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  acaStatus: {
    control: 'select',
    options: Object.values(AcaStatus),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.acaStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  copilotStatus: {
    control: 'select',
    options: Object.values(Status),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  runtimeStatus: {
    control: 'select',
    options: Object.values(Status),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.runtimeStatus},
      category: 'WorkbenchStoreContext',
    },
  },
  // Entitlement
  copilotPlan: {
    control: 'select',
    options: Object.values(CopilotPlan),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotPlan},
      category: 'WorkbenchStoreContext',
    },
  },
  copilotLicenseType: {
    control: 'select',
    options: Object.values(CopilotLicenseType),
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotLicenseType},
      category: 'WorkbenchStoreContext',
    },
  },
  copilotChatQuota: {
    control: 'select',
    options: ['under', 'near', 'over'],
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotChatQuota},
      category: 'WorkbenchStoreContext',
    },
  },
  copilotPremiumInteractionsQuota: {
    control: 'select',
    options: ['under', 'near', 'over'],
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotPremiumInteractionsQuota},
      category: 'WorkbenchStoreContext',
    },
  },
  copilotOveragesEnabled: {
    control: 'boolean',
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.copilotOveragesEnabled.toString()},
      category: 'WorkbenchStoreContext',
    },
  },
  codespaceComputeAllowed: {
    control: 'boolean',
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.codespaceComputeAllowed.toString()},
      category: 'WorkbenchStoreContext',
    },
  },
  codespaceComputeHoursQuota: {
    control: 'select',
    options: ['under', 'near', 'over'],
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.codespaceComputeHoursQuota},
      category: 'WorkbenchStoreContext',
    },
  },
  codespaceSessionsAllowed: {
    control: 'boolean',
    table: {
      defaultValue: {summary: workbenchStoreContextDecoratorArgs.codespaceSessionsAllowed.toString()},
      category: 'WorkbenchStoreContext',
    },
  },
}

export const withWorkbenchStoreContext: Decorator = (Story, {args}) => {
  const contextValue = {
    ...initialState,
    ...args,
    setReadOnly: action('setReadOnly'),
    onError: action('onError'),
    onConnected: action('onConnected'),
    onDisconnected: action('onDisconnected'),
    onIdle: action('onIdle'),
    onStatus: action('onStatus'),
    onCodespaceStatus: action('onCodespaceStatus'),
    onSuccess: action('onSuccess'),
    reloadQuota: action('reloadQuota'),
  } as WorkbenchStoreContext

  return (
    <WorkbenchStoreContext.Provider value={contextValue}>
      <Story />
    </WorkbenchStoreContext.Provider>
  )
}
