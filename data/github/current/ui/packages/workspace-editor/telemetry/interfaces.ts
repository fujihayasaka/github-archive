/**
 * Type definitions for telemetry context and metadata.
 * The metadata objects and telemetry events closely follow
 * the events modeled in the [Workspace Editor Telemetry Events](https://docs.google.com/document/d/1diQuexszf6hiFAhAoYhgKNqemx_9pGJ1ueW4hU73y_k/edit) doc.
 */

/**
 * Telemetry metadata for the `global` context.
 */
export interface IGlobalMetadata {
  /** Pull Request ID. */
  pull_request_id: string
  /** Enabled feature flags. */
  feature_flags: Record<string, boolean>
  /** Repository ID. */
  repository_id: number
  /** Branch name. */
  branch_name: string
}

/**
 * Telemetry metadata for the `editor` context.
 */
export interface IEditorMetadata {
  // Editor session ID.
  session_id: string
  /** Editor version. */
  version: string
}

/**
 * Telemetry metadata for the `lsp` context.
 */
export interface ILspMetadata {
  // Editor session ID.
  session_id: string
  /** Connection ID for the LSP channel. */
  connection_id?: string
  /** ID of the LSP provider (e.g., "codespace", "client", etc.) */
  provider_id: string
  /** ID of language the LSP services are provided for (e.g., "typescript", "python", etc.) */
  language_id: string
  /** Name of the LSP server process. */
  server_name: string
  /** Build version of the LSP server process. */
  server_version: string
}

/**
 * Telemetry metadata for the `EditorSuggestion` context.
 */
export interface IEditorSuggestionMetadata {
  // Unique ID of the suggestion.
  suggestion_id: string
  /** Type of the suggestion (e.g. "user-review", "copilot-review", "ghas-autofix", etc.) */
  type: string
  /** ID of suggestion provider (e.g., "copilot", "user", "ghas-autofix", etc.) */
  provider_id: string
  /** Build version of the provider (e.g., the model version for copilot). */
  provider_version?: string
}

/**
 * Telemetry metadata for the `terminal` context.
 */
export interface ITerminalMetadata {
  /** Terminal session ID. */
  session_id: string
  /** Name of the current shell. */
  shell_name?: string
  /** ID of the current connection. */
  connection_id?: string
}

/**
 * Telemetry metadata for the `TerminalSuggestion` context.
 */
export interface ITerminalSuggestionMetadata {
  /** Unique ID of the suggestion. */
  suggestion_id: string
  /** Type of the suggestion (e.g. "user-requested", "hint", etc.) */
  type: string
  /** ID of suggestion provider (e.g., "copilot" etc.) */
  provider_id: string
  /** Build version of the provider (e.g., the model version for copilot). */
  provider_version?: string
}

// Telemetry metadata for the `port` context.
export interface IPortMetadata {
  /** Session ID of the port. */
  session_id: string
  /** Connection ID for the port channel. */
  connection_id?: string
  /** Protocol of the port (e.g., "TCP", "UDP", etc.) */
  protocol?: string
  /** ID of the port-forwarding provider (e.g., "codespaces", "basis", etc.) */
  provider_id: string
  /** Version of port provider application. */
  provider_version?: string
  /** Port number of the forwarded port(source). */
  forwarded_port_number?: number
  /** Port number of the destination port(sink). */
  destination_port_number?: number
}

/**
 * Telemetry metadata for the `Codespace` context.
 */
export interface ICodespaceMetadata {
  /** ID of an associated Codespace. */
  codespace_id?: string
  /** Associated Codespace session ID. */
  codespace_session_id?: string
  /** ID of the main Codespace connection. */
  connection_id?: string
  /** ID of the Codespace cluster. */
  cluster_id?: string
}

export interface IGeneratedFixMetadata {
  /** Comment ID */
  comment_id?: number
  /** Commit OID */
  commit_oid?: string
  /** A generated hash that represents a unique state of the comments at the time
   * of classification/fix suggestion. Any new comments or comment edits will
   * change this value. */
  comment_version?: string
  /** Unique ID for this suggestion request. Same value is used for
   * classification and fix generation */
  suggestion_request_id?: string
}

export type IValidationMetadata = {
  /** Validation session ID. */
  session_id: string
  /** Repository/App type (react, web-app, backend etc.) */
  app_type?: string
}

/**
 * Supported analytics context names.
 */
export type TAnalyticsContextName =
  | 'global'
  | 'editor'
  | 'lsp'
  | 'editor.suggestion'
  | 'terminal'
  | 'terminal.suggestion'
  | 'port'
  | 'codespace'
  | 'generated_fix'
  | 'validation'

/**
 * Complete telemetry metadata object.
 */
export interface IMetadata {
  /** Global metadata. */
  global?: IGlobalMetadata
  /** Editor metadata. */
  editor?: IEditorMetadata
  /** LSP metadata. */
  lsp?: ILspMetadata
  /** Editor suggestion metadata. */
  editor_suggestion?: IEditorSuggestionMetadata
  /** Terminal metadata. */
  terminal?: ITerminalMetadata
  /** Terminal suggestion metadata. */
  terminal_suggestion?: ITerminalSuggestionMetadata
  /** Port metadata. */
  port?: IPortMetadata
  /** Codespace metadata. */
  codespace?: ICodespaceMetadata
  /** Generated suggestions metadata */
  generated_fix?: IGeneratedFixMetadata
  /** Validation metadata */
  validation?: IValidationMetadata
}

/**
 * Well-known telemetry event names for the `editor` context.
 */
export type TEditorEventName =
  | 'editor.start'
  | 'editor.commit'
  | 'editor.reset'
  | 'editor.file-edit'
  | 'editor.sync-failure'
  | 'editor.local-file-storage'

/**
 * Well-known telemetry event names for the `terminal` context.
 */
export type TTerminalEventName = 'terminal.open' | 'terminal.ready' | 'terminal.fix_build'

/**
 * Well-known telemetry event names for the `codespace` context.
 */
export type TCodespaceEventName = 'codespace.requested' | 'codespace.created' | 'codespace.ready' | 'codespace.error'

/**
 * Well-known telemetry event names for the codespace availability stream.
 */
export type TAvailabilityChannelEventName = 'channel.opened' | 'channel.closed' | 'channel.error'

/**
 * Well-known telemetry event names for API requests
 */
export type TReactQueryEventName = 'react-query.success' | 'react-query.error'

/**
 * Events related to the validation story
 */
export type TValidationEventName =
  | 'validation.task.start'
  | 'validation.task.end'
  | 'validation.channel.created'
  | 'validation.configure.clicked'
  | 'validation.configure.saved'
  | 'validation.configure.dismissed'
  | 'validation.terminal.open'
  | 'validation.terminal.close'
  | 'validation.terminal.run'
  | 'validation.terminal.connected'
  | 'validation.output.open'
/**
 * Well-known telemetry events for user interactions
 */
export type TUserInteractionsEventName =
  | 'generated-fix.opened'
  | 'generated-fix.applied'
  | 'suggestion.dismissed'
  | 'suggestion.reopened'
  | 'right-panel.open'
  | 'right-panel.close'

export type TGeneratedFixEventName =
  | 'get-blob-data.success'
  | 'get-blob-data.error'
  | 'get-comment-classification.success'
  | 'get-comment-classification.error'
  | 'get-generated-fix.success'
  | 'get-generated-fix.error'

/**
 * All well-known telemetry event names.
 */
export type TTelemetryEventName =
  | TEditorEventName
  | TTerminalEventName
  | TCodespaceEventName
  | TAvailabilityChannelEventName
  | TReactQueryEventName
  | TUserInteractionsEventName
  | TGeneratedFixEventName
  | TValidationEventName

/**
 * Function type to send an analytics event with current context metadata.
 */
export type SendAnalyticsEventFunction<T = TTelemetryEventName> = (
  eventName: T,
  properties?: TTelemetryPropertyBag,
) => void

/**
 * Possible telemetry value types.
 */
export type TTelemetryValue = string | number | boolean | null

/**
 * Type for telemetry property bag that can contain any generic telemetry key/value records.
 */
export type TTelemetryPropertyBag = Record<string, TTelemetryValue>

/**
 * Generic analytics context props.
 */
interface IKnownAnalyticsContextProps<T> {
  /** Name of the context. */
  name: TAnalyticsContextName
  /** Function to retrieve context metadata. */
  metadata: () => T
  /** Callback that is called the first time the context component is rendered. */
  onStart?: (sendEvent: SendAnalyticsEventFunction) => void
}

/**
 * Global analytics context props.
 */
export interface IGlobalAnalyticsContextProps extends IKnownAnalyticsContextProps<IGlobalMetadata> {
  /** Name of the context. */
  name: 'global'
  /** Function to retrieve global metadata. */
  metadata: () => IGlobalMetadata
}

/**
 * Editor analytics context props.
 */
export interface IEditorAnalyticsContextProps extends IKnownAnalyticsContextProps<IEditorMetadata> {
  /** Name of the context. */
  name: 'editor'
  /** Function to retrieve editor metadata. */
  metadata: () => IEditorMetadata
}

/**
 * LSP analytics context props.
 */
export interface ILspAnalyticsContextProps extends IKnownAnalyticsContextProps<ILspMetadata> {
  /** Name of the context. */
  name: 'lsp'
  /** Function to retrieve LSP metadata. */
  metadata: () => ILspMetadata
}

/**
 * Editor suggestion analytics context props.
 */
export interface IEditorSuggestionAnalyticsContextProps extends IKnownAnalyticsContextProps<IEditorSuggestionMetadata> {
  /** Name of the context. */
  name: 'editor.suggestion'
  /** Function to retrieve editor suggestion metadata. */
  metadata: () => IEditorSuggestionMetadata
}

/**
 * Terminal analytics context props.
 */
export interface ITerminalAnalyticsContextProps extends IKnownAnalyticsContextProps<ITerminalMetadata> {
  /** Name of the context. */
  name: 'terminal'
  /** Function to retrieve terminal metadata. */
  metadata: () => ITerminalMetadata
}

/**
 * Terminal suggestion analytics context props.
 */
export interface ITerminalSuggestionAnalyticsContextProps
  extends IKnownAnalyticsContextProps<ITerminalSuggestionMetadata> {
  /** Name of the context. */
  name: 'terminal.suggestion'
  /** Function to retrieve terminal suggestion metadata. */
  metadata: () => ITerminalSuggestionMetadata
}

/**
 * Port analytics context props.
 */
export interface IPortAnalyticsContextProps extends IKnownAnalyticsContextProps<IPortMetadata> {
  /** Name of the context. */
  name: 'port'
  /** Function to retrieve port metadata. */
  metadata: () => IPortMetadata
}

/**
 * Codespace analytics context props.
 */
export interface ICodespaceAnalyticsContextProps extends IKnownAnalyticsContextProps<ICodespaceMetadata> {
  /** Name of the context. */
  name: 'codespace'
  /** Function to retrieve codespace metadata. */
  metadata: () => ICodespaceMetadata
}

export interface IGeneratedFixAnalyticsContextProps extends IKnownAnalyticsContextProps<IGeneratedFixMetadata> {
  /** Name of the context. */
  name: 'generated_fix'
  /** Function to retrieve generated fix metadata. */
  metadata: () => IGeneratedFixMetadata
}

export interface IValidationAnalyticsContextProps extends IKnownAnalyticsContextProps<IValidationMetadata> {
  /** Name of the context. */
  name: 'validation'
  /** Function to retrieve generated fix metadata. */
  metadata: () => IValidationMetadata
}

/**
 * Global analytics context props.
 */
export type TAnalyticsContextProps =
  | IGlobalAnalyticsContextProps
  | IEditorAnalyticsContextProps
  | ILspAnalyticsContextProps
  | IEditorSuggestionAnalyticsContextProps
  | ITerminalAnalyticsContextProps
  | ITerminalSuggestionAnalyticsContextProps
  | IPortAnalyticsContextProps
  | ICodespaceAnalyticsContextProps
  | IGeneratedFixAnalyticsContextProps
  | IValidationAnalyticsContextProps
