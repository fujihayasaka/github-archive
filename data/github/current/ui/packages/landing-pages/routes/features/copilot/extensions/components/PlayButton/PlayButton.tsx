import {useEffect, useRef, useState} from 'react'

import {PauseIcon, PlayIcon} from '../CopilotIcons/CopilotIcons'

interface PlayButtonProps {
  scene: 'hero' | 'heroUI' | 'ctaBanner'
  ariaLabels: {
    play: string
    pause: string
  }
}

const defaultProps: Partial<PlayButtonProps> = {}

const PlayButton: React.FC<PlayButtonProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {scene, ariaLabels} = initializedProps

  const [isPaused, setIsPaused] = useState<boolean>(false)
  const wrapperRef = useRef<HTMLButtonElement | null>(null)

  useEffect(() => {
    // Syncs the state with the WebGL-assigned class as the source of truth
    if (!wrapperRef.current) return

    const observer = new MutationObserver(([entry]) => {
      if (!entry?.target) return

      setIsPaused((entry.target as HTMLElement).classList.contains('isPaused'))
    })

    observer.observe(wrapperRef.current, {
      attributeFilter: ['class'],
    })

    return () => {
      observer.disconnect()
    }
  }, [])

  return (
    <button
      aria-label={ariaLabels[isPaused ? 'play' : 'pause']}
      ref={wrapperRef}
      className={`lp-pauseButton lp-pauseButton--${scene}
        ${scene === 'hero' ? 'js-hero-pause-button' : ''}
        ${scene === 'heroUI' ? 'js-heroui-pause-button' : ''}
        ${scene === 'ctaBanner' ? 'js-cta-pause-button' : ''}
      `}
    >
      {isPaused ? <PlayIcon /> : <PauseIcon />}
    </button>
  )
}

export default PlayButton
