import {useRef, lazy, Suspense} from 'react'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'

import {CTABanner, Section} from '@primer/react-brand'

import type {GenericSectionWithIds, GenericContent} from '../../../../brand/lib/types/contentful'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'
import {useDomReady} from '../../../../lib/utils/platform'

import {Spacer} from '../../_shared'

import {CtaGroup} from '../../_components/CtaGroup/CtaGroup'

const CtaWebGL = lazy(() => import('../../CtaWebGL'))

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function CtaSection(props: Props) {
  const {contentfulContent} = props

  const {ctaSectionContent} = contentfulContent.ids as {
    ctaSectionContent: GenericContent
  }

  const {heading, subheading, ctas} = ctaSectionContent?.fields

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
        {ctaSectionContent && heading ? <CTABanner.Heading as="h2">{heading}</CTABanner.Heading> : null}

        {ctaSectionContent && subheading ? (
          <CTABanner.Description className="lp-Cta-description">
            {documentToPlainTextString(subheading)}
          </CTABanner.Description>
        ) : null}

        {ctas ? <CtaGroup contentfulContent={ctas} location="bottom_cta_section" /> : null}
      </CTABanner>
    </Section>
  )
}
