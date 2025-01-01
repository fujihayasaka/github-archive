import {useChatMessageLoopReference} from './use-chat-message-loop-reference'
import {LoopBlockContent} from './LoopBlockContent'

export interface ReadOnlyLoopBlockProps {
  isStreaming?: boolean
}

export function ReadOnlyLoopBlock({isStreaming}: ReadOnlyLoopBlockProps) {
  const loop = useChatMessageLoopReference()

  return <LoopBlockContent loop={loop} isStreaming={isStreaming} />
}
