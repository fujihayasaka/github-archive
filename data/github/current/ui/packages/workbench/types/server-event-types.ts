type ServerHealthEventType = 'connected' | 'heartbeat' | 'server:ready'
type BuildStatusEventType = 'build:started' | 'build:success' | 'build:failed'
type AgentStatusEventType = 'agent:started' | 'agent:update' | 'agent:succeeded' | 'agent:failed'
type SuggestionEventType = 'suggestion:creating' | 'suggestion:completed'
type IterationEventType = 'iteration:committed' | 'iteration:created'
type FileEventType = 'file:create:started' | 'file:create:succeeded' | 'file:update:started' | 'file:update:succeeded'
type ControlEventType = 'complete'
type EventType =
  | ServerHealthEventType
  | BuildStatusEventType
  | AgentStatusEventType
  | SuggestionEventType
  | FileEventType
  | IterationEventType
  | ControlEventType

interface BaseServerEvent {
  type: EventType
  timestamp: string
}

// Server health events let us know the status of our connection to the server.
export interface ConnectedEvent extends BaseServerEvent {
  type: 'connected'
  details: {
    currentIterationId?: number
  }
}

export interface HeartbeatEvent extends BaseServerEvent {
  type: 'heartbeat'
}

export interface ServerReadyEvent extends BaseServerEvent {
  type: 'server:ready'
}

// Build status events let us know the status of the build process as reported by Vite.
export interface BuildStartedEvent extends BaseServerEvent {
  type: 'build:started'
  details: {
    file?: string
  }
}

export interface BuildSuccessEvent extends BaseServerEvent {
  type: 'build:success'
  details: {
    file?: string
  }
}

export interface BuildFailedEvent extends BaseServerEvent {
  type: 'build:failed'
  details: {
    error?: {
      message?: string
    }
  }
}

// Agent Status events let us know the status of the agent response.
export interface AgentStartedEvent extends BaseServerEvent {
  type: 'agent:started'
  details: {
    requestId: string
    iterationId: number
    parentId?: number | null
    prompt: string
  }
}

export interface AgentUpdateEvent extends BaseServerEvent {
  type: 'agent:update'
  details: {
    requestId: string
    iterationId: number
    parentId?: number | null
    message: string
  }
}

export interface AgentSucceededEvent extends BaseServerEvent {
  type: 'agent:succeeded'
  details: {
    requestId: string
    iterationId: number
    parentId?: number | null
    commitSha: string
    fileModifications: Array<{path: string; action: 'created' | 'modified' | 'deleted'}>
  }
}
export interface AgentFailedEvent extends BaseServerEvent {
  type: 'agent:failed'
  details: {
    requestId: string
    iterationId: number
    parentId?: number | null
    error: {
      message: string
      statusCode: number
    }
  }
}

// Suggestion events let us know when suggestions are available.

export interface SuggestionCompletedEvent extends BaseServerEvent {
  type: 'suggestion:completed'
  details: {
    requestId: string
    iterationId: number
    suggestions: string[]
  }
}

// File events let us know when files are created or updated.
export interface FileCreateStartedEvent extends BaseServerEvent {
  type: 'file:create:started'
  details: {
    requestId: string
    iterationId: number
    path: string
  }
}
export interface FileCreateSucceededEvent extends BaseServerEvent {
  type: 'file:create:succeeded'
  details: {
    requestId: string
    iterationId: number
    path: string
  }
}
export interface FileUpdateStartedEvent extends BaseServerEvent {
  type: 'file:update:started'
  details: {
    requestId: string
    iterationId: number
    path: string
  }
}
export interface FileUpdateSucceededEvent extends BaseServerEvent {
  type: 'file:update:succeeded'
  details: {
    requestId: string
    iterationId: number
    path: string
  }
}

export interface IterationCommittedEvent extends BaseServerEvent {
  type: 'iteration:committed'
  details: {
    iterationId: number
    commitSha: string
    prompt?: string
    suggestions?: string[]
    iteration_type: 'ai' | 'user'
    parentId: number | null
    files: Record<string, {editType: 'create' | 'update' | 'delete' | 'rename'; fileName: string}>
  }
}

export interface IterationCreatedEvent extends BaseServerEvent {
  type: 'iteration:created'
  details: {
    parentId: number | undefined
    iterationId: number
    commitSha: string
    prompt: string
    iteration_type: 'ai' | 'user'
  }
}

// Control events for stream management
export interface CompleteEvent extends BaseServerEvent {
  type: 'complete'
}

type ServerHealthEvent = ConnectedEvent | HeartbeatEvent | ServerReadyEvent
type BuildStatusEvent = BuildStartedEvent | BuildSuccessEvent | BuildFailedEvent
type AgentStatusEvent = AgentStartedEvent | AgentUpdateEvent | AgentSucceededEvent | AgentFailedEvent
type SuggestionEvent = SuggestionCompletedEvent
type FileEvent = FileCreateStartedEvent | FileCreateSucceededEvent | FileUpdateStartedEvent | FileUpdateSucceededEvent
type ControlEvent = CompleteEvent

export type ServerEvent =
  | ServerHealthEvent
  | BuildStatusEvent
  | AgentStatusEvent
  | SuggestionEvent
  | FileEvent
  | IterationCommittedEvent
  | IterationCreatedEvent
  | ControlEvent
