import CopilotHead from './copilot-head/copilotHead'
import common from './copilot-head/common'
import mouseMng from './copilot-head/mouseMng'
import controls from './copilot-head/controls'
import assets from './copilot-head/assets'

import {Box} from '@primer/react-brand'
import {analyticsEvent} from '../../../../../lib/analytics'
import {useRef, useEffect} from 'react'
import {hasWebGLSupport} from '../../../../../lib/utils/platform'

export default function CopilotHeadWebGL() {
  const copilotHeadWrapperRef = useRef<HTMLDivElement>(null)
  const assetLoaded = useRef(false)

  useEffect(() => {
    if (!hasWebGLSupport()) return
    const copilotHeadWrapper = copilotHeadWrapperRef.current
    if (!copilotHeadWrapper) return
    const canvas = copilotHeadWrapper.querySelector('canvas') as HTMLCanvasElement
    if (!canvas) return

    common.init(copilotHeadWrapper, canvas)
    controls.init()
    mouseMng.init()

    const controlHead = new CopilotHead()
    if (!assetLoaded.current) {
      assets.load(() => {
        controlHead.init()
        assetLoaded.current = true
      })
    }

    common.scene.add(controlHead.group)

    let resizeOrScrollTimeout: number | null = null
    let animationFrameId: number | null = null

    const handleResizeOrScroll = () => {
      if (resizeOrScrollTimeout) {
        window.cancelAnimationFrame(resizeOrScrollTimeout)
        resizeOrScrollTimeout = null
      }

      resizeOrScrollTimeout = window.requestAnimationFrame(() => {
        common.resize()
      })
    }

    /**
     * Animate
     */

    const startAnimation = () => {
      const tick = () => {
        common.update()
        mouseMng.update()

        // Update controls
        controlHead.update()

        // Render
        common.renderer.render(common.scene, common.camera)

        // Call tick again on the next frame
        animationFrameId = window.requestAnimationFrame(tick)
      }

      tick()

      // eslint-disable-next-line github/prefer-observers, @eslint-react/web-api/no-leaked-event-listener
      window.addEventListener('resize', handleResizeOrScroll)
      // eslint-disable-next-line github/prefer-observers, @eslint-react/web-api/no-leaked-event-listener
      window.addEventListener('scroll', handleResizeOrScroll)
    }

    const stopAnimation = () => {
      if (animationFrameId) {
        window.cancelAnimationFrame(animationFrameId)
        animationFrameId = null
      }

      window.removeEventListener('resize', handleResizeOrScroll)
      window.removeEventListener('scroll', handleResizeOrScroll)
    }

    const intersectionObserverCallback = (entries: IntersectionObserverEntry[]) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          startAnimation()
        } else {
          stopAnimation()
        }
      }
    }

    const observer = new IntersectionObserver(intersectionObserverCallback, {
      threshold: 0.1,
    })

    if (copilotHeadWrapperRef.current) {
      observer.observe(copilotHeadWrapperRef.current)
    }

    return () => {
      assetLoaded.current = true
    }
  }, [])

  return (
    <Box className="lp-Hero-head hide-reduced-motion">
      <div className="lp-Hero-headSize">
        <div className="lp-Hero-headBlink" ref={copilotHeadWrapperRef}>
          <canvas {...analyticsEvent({action: 'copilot_head', tag: 'canvas', context: 'hero', location: 'hero'})} />
        </div>
      </div>
    </Box>
  )
}
