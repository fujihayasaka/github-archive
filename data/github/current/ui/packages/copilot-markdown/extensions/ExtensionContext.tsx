import {createContext} from 'react'

interface ExtensionContext {
  isStreaming?: boolean
  chatMode?: 'assistive' | 'immersive'
}

/**
 * Shared context for React blocks to get state.
 */
export const ExtensionContext = createContext<ExtensionContext>({})
