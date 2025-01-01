import {BreakpointSize, Image, Testimonial, useWindowSize} from '@primer/react-brand'
import {useEffect, useMemo, useRef, useState} from 'react'

import {COPY} from '../../../Index.data'
import {Spacer} from '../../../../../components/Spacer'
import useIntersectionObserver from '../../../../../../../lib/hooks/useIntersectionObserver'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../../utils/responsive'
import useMotion from './Testimonials.motion'
import {checkPrefersReducedMotion} from '../../../../../../../lib/utils/platform'

interface TestimonialsProps {}

const defaultProps: Partial<TestimonialsProps> = {}

const Testimonials: React.FC<TestimonialsProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const wrapperRef = useRef<HTMLDivElement>(null)

  const windowSize = useWindowSize()
  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )

  const isSmallHeight = useMemo(
    () => (windowSize?.height && windowSize.height < BREAKPOINT_DESKTOP_MIN_HEIGHT) || false,
    [windowSize],
  )

  const {isIntersecting: isInView} = useIntersectionObserver(
    wrapperRef,
    {
      threshold: {mobile: 0.15, desktop: 0.4},
      isOnce: true,
    },
    !isSmallHeight && isDesktopView,
  )

  const {show, finish} = useMotion({containerRef: wrapperRef})

  useEffect(() => {
    if (isInView) {
      if (!shouldReduceMotion) show()
      else finish()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isInView])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  useEffect(() => {
    setIsMounted(true)
  }, [])

  return (
    <section ref={wrapperRef} id="testimonials" className="lp-Testimonials">
      <div className="fp-Section-container lp-TestimonialsContainer">
        <Spacer size="96px" size768="128px" />

        <div className="lp-TestimonialsVisual lp-TestimonialsVisual--1">
          <Image src="/images/modules/site/copilot/extensions/testimonial-bg-1.webp" width={414} alt="" />
        </div>
        <div className="lp-TestimonialsVisual lp-TestimonialsVisual--2">
          <Image src="/images/modules/site/copilot/extensions/testimonial-bg-2.webp" width={588} alt="" />
        </div>

        <Testimonial quoteMarkColor="default" size="large" className="lp-Testimonial">
          <Testimonial.Quote className="lp-TestimonialQuote">
            {/* eslint-disable-next-line react/no-danger */}
            <span dangerouslySetInnerHTML={{__html: COPY.testimonial.quote}} />
          </Testimonial.Quote>
          <Testimonial.Name position={COPY.testimonial.position}>{COPY.testimonial.name}</Testimonial.Name>
        </Testimonial>
      </div>
    </section>
  )
}

export default Testimonials
