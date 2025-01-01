import type {ILspMetadata} from '@github-ui/workspace-editor/telemetry/interfaces'

import type {GlobalMetadata} from './global/GlobalAnalytics'

export interface Metadata {
  global?: GlobalMetadata
  lsp?: ILspMetadata
}

export type MetadataSources = GlobalMetadata | ILspMetadata | {}
