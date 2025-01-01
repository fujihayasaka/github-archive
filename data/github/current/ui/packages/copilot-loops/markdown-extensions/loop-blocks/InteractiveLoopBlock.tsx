import {Button} from '@primer/react'
import {useChatMessageLoopReference} from './use-chat-message-loop-reference'
import {LoopBlockContent} from './LoopBlockContent'
import {useLoop} from '../../hooks/queries/use-loop'
import {useLoopOperations} from '../../hooks/use-loop-operations'

export interface InteractiveLoopBlockProps {
  isStreaming?: boolean
}

export function InteractiveLoopBlock({isStreaming}: InteractiveLoopBlockProps) {
  const loopFromChat = useChatMessageLoopReference()
  const {updateLoop} = useLoopOperations()
  const {data: loop} = useLoop()
  const loopExists = loop?.id

  const handleRestoreLoop = () => {
    if (!loop || !loopExists || !loopFromChat) return

    updateLoop(loopFromChat)
  }

  const restoreButton =
    loopExists && !isStreaming ? (
      <Button variant="invisible" onClick={handleRestoreLoop}>
        Restore
      </Button>
    ) : null

  return <LoopBlockContent loop={loopFromChat} headerButton={restoreButton} isStreaming={isStreaming} />
}
