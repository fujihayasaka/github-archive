import {
  type CopilotChatEntitlementQuotas,
  CopilotLicenseType,
  CopilotPlan,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export interface WorkbenchStoreReducer {}

/* Define the services that can be statused */
export const Service = {
  CODESPACE: 'codespace',
  VITE: 'vite',
  AGENT: 'agent',
  FILE_SYNCER: 'fileSyncer',
  DESIGNER: 'designer',
  ACA: 'aca',
  COPILOT: 'copilot',
  RUNTIME: 'runtime',
} as const
type Service = (typeof Service)[keyof typeof Service]

/* Define the default statuses that can be assigned to a service */
export const Status = {
  DISCONNECTED: 'disconnected',
  CONNECTED: 'connected',
  ERROR: 'error',
  IDLE: 'idle',
} as const
type Status = (typeof Status)[keyof typeof Status]

/*
  Define statuses for services that non-default states. To add a custom status:
    1. add a new ${Service}Status const and type, see AgentStatus
    2. add a new ${Service}: ${Service}Status to the WorkbenchStoreState and omit the default status
    3. add a new case to StatusEvent {service: ${service}, status: ${Service}Status}
*/
export const AgentStatus = {
  ...Status,
  GENERATING: 'generating',
} as const
export type AgentStatus = (typeof AgentStatus)[keyof typeof AgentStatus]

export const CodespaceStatus = {
  ...Status,
  STARTING: 'starting',
  NO_GIT: 'noGit',
  NO_NODE_MODULES: 'noNodeModules',
} as const
export type CodespaceStatus = (typeof CodespaceStatus)[keyof typeof CodespaceStatus]

export const AcaStatus = {
  NO_RESOURCES: 'noResources',
  RESOURCES_CREATED: 'resourcesCreated',
} as const
export type AcaStatus = (typeof AcaStatus)[keyof typeof AcaStatus]

export const AnyStatus = {
  ...Status,
  ...AgentStatus,
  ...CodespaceStatus,
  ...AcaStatus,
}
export type AnyStatus = (typeof AnyStatus)[keyof typeof AnyStatus]

type CodespaceComputeLimits = {
  computeHours: number
}
type CodespaceComputeRemaining = CodespaceComputeLimits & {
  computeHoursPercentage: number
}

export type EntitlementBase = {
  allowed?: boolean
  licenseType?: CopilotLicenseType
  plan?: CopilotPlan
  quotas?: unknown
}

export const EntitledService = {
  COPILOT: 'copilot',
  CODESPACE_COMPUTE: 'codespaces_compute',
  CODESPACE_SESSIONS: 'codespaces_sessions',
  BILLING_STATUS: 'billing_status',
  USER_STATUS: 'user_status',
} as const
export type EntitledService = (typeof EntitledService)[keyof typeof EntitledService]

export type Entitlements = {
  [EntitledService.COPILOT]: EntitlementBase & {
    allowed?: never
    licenseType: CopilotLicenseType
    plan: CopilotPlan
    quotas: CopilotChatEntitlementQuotas
  }
  [EntitledService.CODESPACE_COMPUTE]: EntitlementBase & {
    allowed: boolean
    licenseType?: never
    plan?: never
    quotas: {
      limits: CodespaceComputeLimits
      remaining: CodespaceComputeRemaining
      resetDate?: never
    }
  }
  [EntitledService.CODESPACE_SESSIONS]: EntitlementBase & {
    allowed: boolean
    licenseType?: never
    plan?: never
    quotas?: never
  }
  [EntitledService.BILLING_STATUS]: {
    orgTrouble: boolean
    personalTrouble: boolean
  }
  [EntitledService.USER_STATUS]: {
    admin: boolean
    billingUrl?: never
    type?: never
  }
}

/* Default schema for events, e.g. changes to a service status */
type EventPayload = {
  service?: Service
  timestamp?: Date
  details?: unknown
}

/*
  A list of error events is kept separately from the error state of each service
  so error state can be propogated without storing that with the high level status
*/
export const ErrorType = {
  UNKNOWN: 'unknown',
  SPARK_RUNTIME_ERROR: 'sparkRuntimeError',
  SPARK_VITE_ERROR: 'sparkViteError',
} as const
export type ErrorType = (typeof ErrorType)[keyof typeof ErrorType]

export type ErrorEvent = EventPayload & {
  service: Service
  type?: ErrorType
  actionable?: boolean
}

/* Default non-error event schema, maps to setting the state enum for a service */
export type ConnectionEvent = EventPayload & {
  service: Service
}

/* Defaults services to a map of the default status list */
type ConnectionStatusState = Record<Service, Status>
/*
  spreads the default service/status map with non-service state
  also overrides services with their custom status types if defined
*/
export type WorkbenchStoreState = {
  readOnly: boolean
  errors: ErrorEvent[]
  status: Omit<ConnectionStatusState, typeof Service.AGENT | typeof Service.CODESPACE | typeof Service.ACA> & {
    [Service.AGENT]: AgentStatus
    [Service.CODESPACE]: CodespaceStatus
    [Service.ACA]: AcaStatus
  }
  entitlement: Entitlements
}

/*
  Type-safety for sending a status event for a service
  The default status is used unless overwritten per type
*/
export type StatusEvent = ConnectionEvent &
  (
    | {
        service: typeof Service.AGENT
        status: AgentStatus
      }
    | {
        service: typeof Service.CODESPACE
        status: CodespaceStatus
      }
    | {
        service: typeof Service.ACA
        status: AcaStatus
      }
  )

export type WorkbenchStoreAction =
  | {
      type: 'LOCK_READS'
    }
  | {
      type: 'UNLOCK_READS'
    }
  | {
      type: 'ERROR'
      payload: ErrorEvent
    }
  | {
      type: 'CLEAR_ERRORS'
      payload?: Service
    }
  | {
      type: 'CONNECTED'
      payload: ConnectionEvent
    }
  | {
      type: 'DISCONNECTED'
      payload: ConnectionEvent
    }
  | {
      type: 'IDLE'
      payload: ConnectionEvent
    }
  | {
      type: 'STATUS'
      payload: StatusEvent
    }

export const initialState: WorkbenchStoreState = {
  readOnly: false,
  errors: [],
  status: {
    codespace: Status.DISCONNECTED,
    agent: Status.DISCONNECTED,
    fileSyncer: Status.DISCONNECTED,
    vite: Status.DISCONNECTED,
    designer: Status.DISCONNECTED,
    aca: AcaStatus.RESOURCES_CREATED, // not populated
    copilot: Status.CONNECTED, // not populated
    runtime: Status.DISCONNECTED,
  },
  entitlement: {
    [EntitledService.COPILOT]: {
      licenseType: CopilotLicenseType.LicensedLimited,
      plan: CopilotPlan.IndividualFree,
      quotas: {
        limits: {
          chat: Infinity,
          premiumInteractions: Infinity,
        },
        remaining: {
          chat: Infinity,
          chatPercentage: 100,
          premiumInteractions: Infinity,
          premiumInteractionsPercentage: 100,
        },
        resetDate: new Date().toJSON().slice(0, 'XXXX-XX-XX'.length),
        overagesEnabled: false,
      },
    },
    [EntitledService.CODESPACE_COMPUTE]: {
      allowed: false,
      quotas: {
        limits: {
          computeHours: Infinity,
        },
        remaining: {
          computeHours: Infinity,
          computeHoursPercentage: Infinity,
        },
      },
    },
    [EntitledService.CODESPACE_SESSIONS]: {
      allowed: true,
    },
    [EntitledService.BILLING_STATUS]: {
      personalTrouble: false,
      orgTrouble: false,
    },
    [EntitledService.USER_STATUS]: {
      admin: false,
      billingUrl: undefined,
      type: undefined,
    },
  },
}

export function workbenchStoreReducer(state: WorkbenchStoreState, action: WorkbenchStoreAction): WorkbenchStoreState {
  switch (action.type) {
    case 'LOCK_READS': {
      return {
        ...state,
        readOnly: true,
      }
    }
    case 'UNLOCK_READS': {
      return {
        ...state,
        readOnly: false,
      }
    }
    case 'ERROR': {
      const {payload} = action
      const service = payload.service
        ? {
            [payload.service]: Status.ERROR,
          }
        : {}
      return {
        ...state,
        status: {
          ...state.status,
          ...service,
        },
        errors: [...state.errors, payload],
      }
    }
    case 'CLEAR_ERRORS': {
      if (!action.payload) {
        return {
          ...state,
          errors: [],
        }
      }
      const {payload: service} = action
      return {
        ...state,
        errors: [...state.errors.filter(error => error.service !== service)],
      }
    }
    case 'CONNECTED': {
      const {payload} = action
      return {
        ...state,
        status: {
          ...state.status,
          [payload.service]: Status.CONNECTED,
        },
      }
    }
    case 'DISCONNECTED': {
      const {payload} = action
      return {
        ...state,
        status: {
          ...state.status,
          [payload.service]: Status.DISCONNECTED,
        },
      }
    }
    case 'IDLE': {
      const {payload} = action
      return {
        ...state,
        status: {
          ...state.status,
          [payload.service]: Status.IDLE,
        },
      }
    }
    case 'STATUS': {
      const {payload} = action
      return {
        ...state,
        status: {
          ...state.status,
          [payload.service]: payload.status,
        },
      }
    }
    default: {
      return state
    }
  }
}
