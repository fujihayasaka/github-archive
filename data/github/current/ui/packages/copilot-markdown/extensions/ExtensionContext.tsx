import type {CopilotAnnotations} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {createContext} from 'react'

interface ExtensionContext {
  isStreaming?: boolean
  chatMode?: 'assistive' | 'immersive'
  copilotAnnotations?: CopilotAnnotations
  wrapCodeLines?: boolean
  onWrapCodeLinesChange?: (wrap: boolean) => void
}

/**
 * Shared context for React blocks to get state.
 */
export const ExtensionContext = createContext<ExtensionContext>({})
