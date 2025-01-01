import {useCallback, useRef, type RefObject} from 'react'

import {HeroScreenId} from './HeroCarousel.data'
import {eases} from '../../utils/animation'

interface MotionRef {
  visual: RefObject<HTMLDivElement | null>
  onFinish: () => void
  isDesktopView: boolean
}

const useMotion = ({visual, onFinish, isDesktopView}: MotionRef) => {
  const currentAnimations = useRef<Animation[]>([])
  const lastScreenId = useRef<HeroScreenId>(HeroScreenId.code)

  const reset = useCallback(() => {
    if (currentAnimations.current.length) {
      for (const animation of currentAnimations.current) {
        animation.cancel()
      }
    }

    currentAnimations.current = []
  }, [])

  const getVisuals = useCallback(() => {
    if (!visual.current) return []

    const visuals: HTMLElement[] = Array.from(visual.current.querySelectorAll('img, video'))
    return visuals
  }, [visual])

  const showPlan = useCallback(() => {
    const visuals = getVisuals()
    if (!visuals.every(Boolean)) return

    const cursor = visuals[3]
    const tabMenu = visual.current?.querySelector('.lp-HeroCarousel-visual-planMenu') as HTMLElement
    if (!tabMenu) return

    const tabs = Array.from(tabMenu.children) as HTMLElement[]
    if (!tabs.every(Boolean)) return

    const getCursorTranslation = (tabIndex: number, isOffset = false) =>
      !tabs[tabIndex]
        ? ''
        : `translate(calc(${isOffset ? -90 : -100}% + ${tabMenu.offsetLeft}px + ${tabs[tabIndex].offsetLeft}px + ${
            tabs[tabIndex].offsetWidth
          }px), calc(${isOffset ? 100 : 25}% + ${tabMenu.offsetTop}px))`

    visuals[0]!.style.opacity = '1'
    visuals[1]!.style.opacity = '0'
    visuals[2]!.style.opacity = '0'
    cursor!.style.opacity = '0'
    cursor!.style.transform = getCursorTranslation(1, true)

    const inProps = {opacity: 1, translate: '0 0'}
    const outProps = {opacity: 0, translate: '0 0'}

    const step1Cursor = cursor!.animate([{opacity: 0}, {opacity: 1}], {
      delay: 0,
      fill: 'forwards',
      duration: 400,
      easing: eases.easeOutCirc,
    })
    const step2Cursor = cursor!.animate([{transform: getCursorTranslation(1)}], {
      delay: 800,
      fill: 'forwards',
      duration: 800,
      easing: eases.easeOutQuart,
    })
    const step2In = visuals[1]!.animate([outProps, inProps], {
      delay: 2600,
      fill: 'forwards',
      duration: 400,
      easing: eases.easeInOutCirc,
    })
    const step1Out = visuals[0]!.animate([inProps, outProps], {
      delay: 3000,
      fill: 'forwards',
      duration: 400,
    })

    currentAnimations.current.push(step1Cursor)
    currentAnimations.current.push(step2Cursor)
    currentAnimations.current.push(step2In)
    currentAnimations.current.push(step1Out)

    const step3Cursor = cursor!.animate([{transform: getCursorTranslation(2)}], {
      delay: 4200,
      fill: 'forwards',
      duration: 800,
      easing: eases.easeOutQuart,
    })
    const step3In = visuals[2]!.animate([outProps, inProps], {
      delay: 5200,
      fill: 'forwards',
      duration: 400,
      easing: eases.easeInOutCirc,
    })
    const step2Out = visuals[1]!.animate([inProps, outProps], {
      delay: 5600,
      fill: 'forwards',
      duration: 400,
      easing: eases.easeInOutCirc,
    })

    currentAnimations.current.push(step3Cursor)
    currentAnimations.current.push(step3In)
    currentAnimations.current.push(step2Out)
  }, [getVisuals, visual])

  const showCollaborate = useCallback(() => {
    const visuals = getVisuals()
    if (!visuals.every(Boolean)) return

    visuals[0]!.style.opacity = '1'
    visuals[1]!.style.opacity = '0'

    if (!isDesktopView) return

    const step2In = visuals[1]!.animate(
      [
        {
          opacity: 0,
          translate: '20px 0',
        },
        {
          opacity: 1,
          translate: '0 0',
        },
      ],
      {delay: 600, fill: 'forwards', duration: 500, easing: eases.easeInOutCirc},
    )
    currentAnimations.current.push(step2In)
  }, [getVisuals, isDesktopView])

  const showAutomate = useCallback(() => {
    const visuals = getVisuals()
    if (!visuals.every(Boolean)) return

    visuals[0]!.style.opacity = '1'
    visuals[1]!.style.opacity = '0'
    visuals[2]!.style.opacity = '0'

    const translateString = isDesktopView ? '20px 0' : '0 20px'

    const step2In = visuals[1]!.animate(
      [
        {
          opacity: 0,
          translate: translateString,
        },
        {
          opacity: 1,
          translate: '0 0',
        },
      ],
      {delay: 600, fill: 'forwards', duration: 500, easing: eases.easeInOutCirc},
    )
    currentAnimations.current.push(step2In)

    const step3In = visuals[2]!.animate(
      [
        {
          opacity: 0,
          translate: translateString,
        },
        {
          opacity: 1,
          translate: '0 0',
        },
      ],
      {delay: 1200, fill: 'forwards', duration: 500, easing: eases.easeInOutCirc},
    )
    currentAnimations.current.push(step3In)
  }, [getVisuals, isDesktopView])

  const showSecure = useCallback(() => {
    const visuals = getVisuals()
    if (!visuals.every(Boolean)) return

    visuals[0]!.style.opacity = '1'
    visuals[1]!.style.opacity = '0'

    if (!isDesktopView) return

    const step2In = visuals[1]!.animate(
      [
        {
          opacity: 0,
          translate: '20px 0',
        },
        {
          opacity: 1,
          translate: '0 0',
        },
      ],
      {delay: 800, fill: 'forwards', duration: 400, easing: eases.easeInOutCirc},
    )
    currentAnimations.current.push(step2In)
  }, [getVisuals, isDesktopView])

  const show = useCallback(
    async (screenId: HeroScreenId) => {
      lastScreenId.current = screenId
      reset()

      switch (screenId) {
        case HeroScreenId.plan:
          showPlan()
          break
        case HeroScreenId.collaborate:
          showCollaborate()
          break
        case HeroScreenId.automate:
          showAutomate()
          break
        case HeroScreenId.secure:
          showSecure()
          break
      }

      try {
        if (!currentAnimations.current.length) return
        const animationPromises = currentAnimations.current.map(animation => animation.finished)
        await Promise.all(animationPromises)
        onFinish()
      } catch {
        // Ignore errors if the animation is interrupted before finishing
      }
    },
    [onFinish, reset, showAutomate, showCollaborate, showPlan, showSecure],
  )

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

    // If there's nothing to resume, replay the latest animation
    if (!hasResumed) {
      show(lastScreenId.current)
    }
  }, [show])

  const finish = useCallback(
    (screenId: HeroScreenId) => {
      show(screenId)

      // Immediately finish the animations
      if (currentAnimations.current.length) {
        for (const animation of currentAnimations.current) {
          if (animation.playState !== 'idle') {
            animation.finish()
          }
        }
      }
    },
    [show],
  )

  return {show, pause, resume, finish}
}

export default useMotion
