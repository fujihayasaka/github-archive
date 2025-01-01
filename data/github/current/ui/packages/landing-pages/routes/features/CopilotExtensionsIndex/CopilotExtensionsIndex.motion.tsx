import {useCallback} from 'react'

interface MotionRef {
  testimonialRef: React.RefObject<HTMLSpanElement>
}

const useMotion = ({testimonialRef}: MotionRef) => {
  const showTestimonial = useCallback(async () => {
    if (!testimonialRef.current) return

    // TODO: Implement animation
  }, [testimonialRef])

  return {
    showTestimonial,
  }
}

export default useMotion
