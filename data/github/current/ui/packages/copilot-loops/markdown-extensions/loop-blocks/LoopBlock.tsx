import {usePipesServiceOptional} from '../../contexts/PipesServiceProvider'
import {ReadOnlyLoopBlock} from './ReadOnlyLoopBlock'
import {InteractiveLoopBlock} from './InteractiveLoopBlock'

export interface LoopBlockProps {
  isStreaming?: boolean
}

export function LoopBlock({isStreaming}: LoopBlockProps) {
  const pipesService = usePipesServiceOptional()
  const hasLoopsContext = !!pipesService

  if (hasLoopsContext) {
    return <InteractiveLoopBlock isStreaming={isStreaming} />
  }

  return <ReadOnlyLoopBlock isStreaming={isStreaming} />
}
