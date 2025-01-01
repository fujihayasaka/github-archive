import {usePipesService} from '../contexts/PipesServiceProvider'
import type {Pipeline} from '../types/app'
import {useNavigate} from 'react-router-dom'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useLoop} from './queries/use-loop'

export function useDuplicateLoop() {
  const pipesService = usePipesService()
  const navigate = useNavigate()
  const {data: loop} = useLoop()

  return async () => {
    if (!loop) return

    const newLoopId = crypto.randomUUID()
    const duplicatedLoop: Pipeline = {
      ...loop,
      id: newLoopId,
      title: loop.title,
      updatedAt: new Date().toISOString(),
    }

    await pipesService.createLoop(duplicatedLoop)
    navigate(`${COPILOT_PATH}/l/${newLoopId}`)
  }
}
