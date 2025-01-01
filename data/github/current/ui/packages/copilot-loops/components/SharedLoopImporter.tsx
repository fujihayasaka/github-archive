import {useEffect, useRef} from 'react'
import {useLocation, useNavigate} from 'react-router-dom'
import {usePipesService} from '../contexts/PipesServiceProvider'
import {sendEvent} from '@github-ui/hydro-analytics'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {decodeSharedLoop, createLoopFromShared} from '../utils/share'

/**
 * Component that handles importing shared loops from URL parameters.
 * This component doesn't render anything visible but processes the shared loop data
 * and redirects the user to the appropriate page after import.
 */
export function SharedLoopImporter() {
  const location = useLocation()
  const navigate = useNavigate()
  const loopsService = usePipesService()
  const firstRun = useRef(true)

  useEffect(() => {
    if (!firstRun.current) return
    firstRun.current = false

    async function importSharedLoop() {
      const redirectPath = `${COPILOT_PATH}/loops`
      try {
        const params = new URLSearchParams(location.search)
        const encodedData = params.get('data')

        if (!encodedData) {
          navigate(redirectPath)
          return
        }

        const loopData = decodeSharedLoop(encodedData)
        if (!loopData) {
          navigate(redirectPath)
          return
        }

        const importedLoop = createLoopFromShared(loopData)
        await loopsService.createLoop(importedLoop)
        sendEvent('dotcom_chat.activate', {target: 'LOOP_IMPORT_SHARED', mode: 'loops'})

        navigate(`${COPILOT_PATH}/l/${importedLoop.id}`)
      } catch {
        // todo: maybe surface an error message on the landing page if we fail at any point?
        navigate(redirectPath)
      }
    }

    importSharedLoop()
  }, [location.search, navigate, loopsService])

  return null
}
