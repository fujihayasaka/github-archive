import {useMemo} from 'react'

import type {CopilotChatManager} from '../utils/copilot-chat-manager'
import type {SkillExecution} from '../utils/copilot-chat-types'
import {useFunctionMetadata} from './FunctionLoadingUtils'

export const FunctionCallBadge = ({
  functionCall,
  manager,
  panelWidth,
  messageInterrupted,
}: {
  functionCall: SkillExecution
  manager: CopilotChatManager
  panelWidth: number | undefined
  messageInterrupted: boolean | undefined
}) => {
  const {functionMetadata, functionRenderer, parsedArgs} = useFunctionMetadata(functionCall)
  const useSelectReference = false // TODO: remove reference selection entirely if it's not coming back

  const interruptedFunctionCall = useMemo<SkillExecution>(
    () => (messageInterrupted && functionCall.status === 'started' ? {...functionCall, status: 'error'} : functionCall),
    [functionCall, messageInterrupted],
  )

  return (
    <>
      {functionMetadata &&
        functionRenderer &&
        parsedArgs &&
        functionRenderer(
          interruptedFunctionCall,
          functionMetadata,
          manager,
          panelWidth,
          parsedArgs,
          useSelectReference,
        )}
    </>
  )
}
