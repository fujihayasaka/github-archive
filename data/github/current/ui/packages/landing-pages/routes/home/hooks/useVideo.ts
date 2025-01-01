import {useCallback, useEffect, useRef} from 'react'
import useIntersectionObserver from '../../../lib/hooks/useIntersectionObserver'

export interface VideoRef {
  videoRef: React.MutableRefObject<HTMLVideoElement | null>
  isPaused: boolean
}

const useVideo = ({videoRef, isPaused}: VideoRef) => {
  const videoSrc = useRef<string>('')
  const currentVideoTime = useRef<number>(-1)

  const {isIntersecting} = useIntersectionObserver(videoRef, {threshold: 0.33, isOnce: true})

  const play = useCallback(() => {
    if (videoRef.current?.readyState && videoRef.current?.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      try {
        videoRef.current.play()
      } catch {
        // Ignore errors
      }
    }
  }, [videoRef])

  const toggle = useCallback(() => {
    if (videoRef.current?.readyState && videoRef.current?.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      try {
        videoRef.current[isPaused ? 'pause' : 'play']()
      } catch {
        // Ignore errors
      }
    }
  }, [isPaused, videoRef])

  const addListeners = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.addEventListener('canplay', play)

      // Safari won't load without an explicit statement
      videoRef.current.load()
    }
  }, [play, videoRef])

  const removeListeners = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.removeEventListener('canplay', play)
    }
  }, [play, videoRef])

  const onVideoTimeUpdate = useCallback((event: React.SyntheticEvent<HTMLVideoElement>) => {
    const video = event.currentTarget as HTMLVideoElement
    if (!video) return

    // Resync the video if we just switched desktop/mobile assets
    if (videoSrc.current !== video.src && currentVideoTime.current >= 0) {
      video.currentTime = currentVideoTime.current
    }

    videoSrc.current = video.src || ''
    currentVideoTime.current = video.currentTime || 0
  }, [])

  useEffect(() => {
    toggle()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isPaused])

  useEffect(() => {
    if (isIntersecting && !isPaused) {
      if (videoRef.current?.readyState && videoRef.current?.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) play()
      else addListeners()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isIntersecting])

  return {
    addListeners,
    removeListeners,
    onVideoTimeUpdate,
  }
}

export default useVideo
