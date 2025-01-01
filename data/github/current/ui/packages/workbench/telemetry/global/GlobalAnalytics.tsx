import type {IKnownAnalyticsContextProps} from '@github-ui/workspace-editor/telemetry/interfaces'

/**
 * Global analytics metadata for Spark
 */
export interface GlobalMetadata {
  // Enabled feature flags
  feature_flags: Record<string, boolean>

  workbench_id: string
  runtime_permanent_name: string
  runtime_session_id: string
  browser_session_id: string
  copilot_access_allowed: boolean
}

/**
 * Global analytics context properties for Spark
 */
export interface GlobalAnalyticsContextProps extends IKnownAnalyticsContextProps<GlobalMetadata> {
  name: 'global'
  metadata: () => GlobalMetadata
}
