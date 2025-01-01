import React, {useCallback, useEffect} from 'react'

import {IconButton} from '@storybook/components'
import {PlayIcon, StopIcon} from '@storybook/icons'

export const ADDON_ID = 'disable-interaction'
export const TOOL_ID = `${ADDON_ID}/tool`

export const INTERACTION_STORAGE_KEY = 'disableInteractions'

export const InteractionToggle = () => {
  const [disableInteractions, setDisableInteractions] = React.useState(
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-react-fc
    window?.localStorage.getItem(INTERACTION_STORAGE_KEY) === 'true',
  )

  useEffect(() => {
    const reducedMotion = matchMedia('(prefers-reduced-motion)')

    if (window?.localStorage.getItem(INTERACTION_STORAGE_KEY) === null && reducedMotion.matches) {
      window?.localStorage?.setItem(INTERACTION_STORAGE_KEY, 'true')
      setDisableInteractions(true)
    }
  }, [])

  const toggleMyTool = useCallback(() => {
    window?.localStorage?.setItem(INTERACTION_STORAGE_KEY, `${!disableInteractions}`)
    setDisableInteractions(!disableInteractions)
      // Refresh the page to cause the interaction to stop/start
      window.location.reload()
  }, [disableInteractions, setDisableInteractions])

  return (
    <IconButton
      key={TOOL_ID}
      aria-label="Disable Interactions"
      onClick={toggleMyTool}
      defaultChecked={disableInteractions}
      aria-pressed={disableInteractions}
    >
      {disableInteractions ? <PlayIcon /> : <StopIcon />}
      <span>Interactions</span>
    </IconButton>
  )
}
