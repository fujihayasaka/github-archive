// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback, useEffect, useRef, type RefObject} from 'react'

import {animate, CUBIC_BEZIER_EASES, EASING_FUNCTIONS} from '../../../utils/animation'

interface MotionRef {
  containerRef: RefObject<HTMLDivElement | null>
  onFinish?: () => void
}

const useMotion = ({containerRef, onFinish}: MotionRef) => {
  const currentAnimations = useRef<Animation[]>([])

  const init = useCallback(() => {
    const testimonial = containerRef.current?.querySelector('.lp-Testimonial') as HTMLElement
    if (!containerRef.current || !testimonial) return

    const quotationMark = testimonial.querySelector('& > div:first-child') as HTMLElement
    const quote = testimonial.querySelector('& > blockquote') as HTMLElement
    const name = testimonial.querySelector('& > div:last-child') as HTMLElement
    const visuals: HTMLElement[] = Array.from(containerRef.current.querySelectorAll('.lp-TestimonialsVisual'))
    if (![quotationMark, quote, name].every(Boolean) || !visuals.length) return

    testimonial.style.opacity = '0'
    quote.style.opacity = '0'
    name.style.opacity = '0'
    visuals[0]!.style.opacity = '0'
    visuals[1]!.style.opacity = '0'
  }, [containerRef])

  const reset = useCallback(() => {
    if (currentAnimations.current.length) {
      for (const animation of currentAnimations.current) {
        animation.cancel()
      }
    }

    currentAnimations.current = []
  }, [])

  const showTestimonials = useCallback(() => {
    const testimonial = containerRef.current?.querySelector('.lp-Testimonial') as HTMLElement
    if (!containerRef.current || !testimonial) return

    const quotationMark = testimonial.querySelector('& > div:first-child') as HTMLElement
    const quote = testimonial.querySelector('& > blockquote') as HTMLElement
    const name = testimonial.querySelector('& > div:last-child') as HTMLElement
    const visuals: HTMLElement[] = Array.from(containerRef.current.querySelectorAll('.lp-TestimonialsVisual'))
    if (![quotationMark, quote, name].every(Boolean) || !visuals.length) return

    init()

    const baseDelay = 200 // ms

    const testimonialTween = animate(
      testimonial,
      [
        {opacity: 0, translate: '0 60px'},
        {opacity: 1, translate: '0 0'},
      ],
      {
        fill: 'forwards',
        delay: baseDelay,
        duration: 400,
        easing: CUBIC_BEZIER_EASES.easeOutCirc,
      },
    )

    const quotationMarkTween = animate(
      quotationMark,
      [
        {scale: 1.2, translate: '7.5% 0'},
        {scale: 1, translate: '0 0'},
      ],
      {
        fill: 'forwards',
        delay: baseDelay,
        duration: 1000,
        easing: CUBIC_BEZIER_EASES.easeInOutCirc,
      },
    )

    const dummy = document.createElement('div')
    const quoteTween = animate(dummy, [{opacity: 0}, {opacity: 1}], {
      onStart: () => {
        quote.style.opacity = '1'
      },
      onUpdate: progress => {
        const easedProgress = EASING_FUNCTIONS.easeOutCirc(progress)
        quote.style.maskImage = `linear-gradient(120deg,
          #000 ${easedProgress * 100}%,
          transparent ${2 * easedProgress * 100}%
        )`
      },
      fill: 'forwards',
      delay: baseDelay + 400,
      duration: 2400,
    })

    const nameTween = animate(
      name,
      [
        {opacity: 0, translate: '0 20px'},
        {opacity: 1, translate: '0 0'},
      ],
      {
        fill: 'forwards',
        delay: baseDelay + 500,
        duration: 600,
        easing: CUBIC_BEZIER_EASES.easeOutCirc,
      },
    )

    currentAnimations.current.push(testimonialTween)
    currentAnimations.current.push(quotationMarkTween)
    currentAnimations.current.push(quoteTween)
    currentAnimations.current.push(nameTween)

    const visual1Tween = animate(
      visuals[0]!.firstElementChild as HTMLElement,
      [
        {opacity: 0, scale: 0.85},
        {opacity: 1, scale: 1},
      ],
      {
        onStart: () => {
          visuals[0]!.style.opacity = '1'
        },
        fill: 'forwards',
        delay: baseDelay + 200,
        duration: 3000,
        easing: CUBIC_BEZIER_EASES.easeOutCirc,
      },
    )

    const visual2Tween = animate(
      visuals[1]!.firstElementChild as HTMLElement,
      [
        {opacity: 0, scale: 0.85},
        {opacity: 1, scale: 1},
      ],
      {
        onStart: () => {
          visuals[1]!.style.opacity = '1'
        },
        fill: 'forwards',
        delay: baseDelay + 300,
        duration: 3000,
        easing: CUBIC_BEZIER_EASES.easeOutCirc,
      },
    )

    currentAnimations.current.push(visual1Tween)
    currentAnimations.current.push(visual2Tween)
  }, [containerRef, init])

  const show = useCallback(async () => {
    reset()
    showTestimonials()

    if (onFinish) {
      try {
        if (!currentAnimations.current.length) return
        const animationPromises = currentAnimations.current.map(animation => animation.finished)
        await Promise.all(animationPromises)
        onFinish()
      } catch {
        // Ignore errors if the animation is interrupted before finishing
      }
    }
  }, [onFinish, reset, showTestimonials])

  const pause = useCallback(() => {
    if (currentAnimations.current.length) {
      for (const animation of currentAnimations.current) {
        if (animation.playState === 'running') {
          animation.pause()
        }
      }
    }
  }, [])

  const resume = useCallback(() => {
    let hasResumed = false
    if (currentAnimations.current.length) {
      for (const animation of currentAnimations.current) {
        if (animation.playState === 'paused') {
          hasResumed = true
          animation.play()
        }
      }
    }

    // If there's nothing to resume, replay the animation
    if (!hasResumed) {
      show()
    }
  }, [show])

  const finish = useCallback(() => {
    show()

    // Immediately finish the animations
    if (currentAnimations.current.length) {
      for (const animation of currentAnimations.current) {
        if (animation.playState !== 'idle') {
          animation.finish()
        }
      }
    }
  }, [show])

  useEffect(() => {
    init()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {show, pause, resume, finish}
}

export default useMotion
