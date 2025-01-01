import {CTABanner, Section} from '@primer/react-brand'

import {Spacer} from './_shared'
import CtaForm from './components/CtaForm/CtaForm'
import {useRef, lazy, Suspense} from 'react'
import useIntersectionObserver from '../../lib/hooks/useIntersectionObserver'
import {useDomReady} from '../../lib/utils/platform'
import {COPY} from './Cta.data'

const CtaWebGL = lazy(() => import('./CtaWebGL'))

export default function Cta() {
  const ctaRef = useRef<HTMLDivElement | null>(null)
  const {isIntersecting: isCtaInView} = useIntersectionObserver(ctaRef, {threshold: 0.4, isOnce: true})
  const isDomReady = useDomReady()

  return (
    <Section id="cta">
      <Spacer size="100px" />
      <div className="lp-Cta-mascots-wrap">
        <svg width="2280" height="1200" aria-hidden="true" />
        {isDomReady && (
          <Suspense fallback={null}>
            <CtaWebGL />
          </Suspense>
        )}
      </div>

      <Spacer size="48px" size1012="80px" />

      <CTABanner
        ref={ctaRef}
        className={`lp-Cta ${isCtaInView ? 'is-visible' : ''}`}
        align="center"
        hasBackground={false}
        hasShadow={false}
      >
        <CTABanner.Heading as="h2">{COPY.heading}</CTABanner.Heading>
        <CTABanner.Description className="lp-Cta-description">{COPY.description}</CTABanner.Description>
        <CtaForm location="bottom_cta_section" />
      </CTABanner>
    </Section>
  )
}
