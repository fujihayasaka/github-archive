/*
 * Shown when the Spark is idle for 30min or longer.
 */

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Banner} from '@primer/react/experimental'
import {useCallback, useEffect, useRef} from 'react'

import {useServerEvents} from '../../workbench/contexts/ServerEventsContext'
import {useCodespaces} from '../../workbench/lsp/use-codespaces'
import type {WorkbenchRoutePayload} from '../../workbench/types/workbench-types'
import {setSubmitTimestamp} from '../../workbench/utilities/copilot-chat'

export function IdleSparkBanner() {
  // TODO: Spark Workbench is moving away from repos, this dependency should be replaced with something
  // else eventually
  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const {reconnect} = useServerEvents()
  const {repo} = payload
  const inputRef = useRef<HTMLInputElement | null>(null)

  // Set inputRef.current after mount
  useEffect(() => {
    inputRef.current = document.querySelector('#iterate-modal-input')
  }, [])

  // This hook is used to resume the idle codespace
  const {recreateCodespace, codespaceState} = useCodespaces(repo)
  const handleClick = useCallback(async () => {
    // For user on either free or paid plans, we can try to resume or create the codespace
    await recreateCodespace()
    // Reconnect to the server events endpoint after the codespace is resumed
    if (codespaceState === 'ready') {
      reconnect()
    }
    // For all users, we need to set the submit timestamp to the current time
    setSubmitTimestamp()
    // Put the focus back on the editor prompt so users can submit their prompt
    // Helps all users to get back to the editor but more important for free users
    inputRef.current?.focus()
  }, [codespaceState, reconnect, recreateCodespace])

  const description = 'This spark is currently read-only due to inactivity. Activate it to continue editing.'
  const primaryAction = <Banner.PrimaryAction onClick={handleClick}>Activate</Banner.PrimaryAction>
  const title = 'Spark editor is idle for too long.'
  const variant = 'warning'

  return (
    <Banner
      className="mx-3 mb-2"
      description={description}
      hideTitle
      primaryAction={primaryAction}
      title={title}
      variant={variant}
    />
  )
}
