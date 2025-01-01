import {useEffect, useState} from 'react'

// We are temporarily avoiding useScreenSize hook, which uses ResizeObserver, to instead use very simple viewport matcher
// This PR (https://github.com/github/github/pull/356476) resulted in a glut of Sentry spikes by using useScreenSize
// See more: https://github.com/github/web-systems/issues/2806#issuecomment-2669731821
export function useViewportWidth() {
  const [viewportWidth, setViewportWidth] = useState(window.innerWidth)

  useEffect(() => {
    const handleResize = () => {
      setViewportWidth(window.innerWidth)
    }

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  return viewportWidth
}
