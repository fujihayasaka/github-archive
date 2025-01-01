import {useRef, useState, lazy, Suspense} from 'react'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'

import {Hero} from '@primer/react-brand'

import {ContentfulLogoSuite} from '@github-ui/swp-core/components/contentful/ContentfulLogoSuite'
import type {PrimerComponentLogoSuite} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLogoSuite'

import type {GenericSectionWithIds, GenericContent, GenericGroup} from '../../../../brand/lib/types/contentful'

import {useDomReady} from '../../../../lib/utils/platform'

import {Spacer} from './../../_shared'

import HeroCarousel from './../../components/HeroCarousel/HeroCarousel'
import HeroCarouselControls from './../../components/HeroCarousel/HeroCarouselControls/HeroCarouselControls'

import {CtaGroup} from '../../_components/CtaGroup/CtaGroup'

import type Assets from './../../webgl-utils/assets'

const IntroHero = lazy(() => import('../../IntroHero'))

type Props = {
  contentfulContent: GenericSectionWithIds
  assetsRef: React.RefObject<Assets>
}

export function HeroSection(props: Props) {
  const {contentfulContent, assetsRef} = props

  const {heroContent, heroCarousel} = contentfulContent.ids as {
    heroContent: GenericContent
    heroCarousel: GenericGroup
  }

  const logosComponent = contentfulContent.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentLogoSuite',
  ) as PrimerComponentLogoSuite | undefined

  const [currentCarouselScreenIndex, setCurrentCarouselScreenIndex] = useState<number>(0)

  const heroRef = useRef<HTMLDivElement | null>(null)
  const isDomReady = useDomReady()

  const setCopyScrollOpacity = (copyScrollOpacity: number) => {
    if (heroRef.current) {
      heroRef.current.style.opacity = `${copyScrollOpacity}` // Set the desired opacity value
    }
  }

  const setCopyScrollScale = (copyScrollScale: number) => {
    if (heroRef.current) {
      heroRef.current.style.transform = `scale(${copyScrollScale})` // Set the desired scale value
    }
  }

  const heroCarouselItems = heroCarousel?.fields.content ? (heroCarousel.fields.content as GenericContent[]) : undefined

  return (
    <section id="hero">
      <div className="lp-Intro">
        {/* Header 72 + Global Banner 42 = 114px */}
        <div className="lp-Intro-gradient" />

        <Spacer size="114px" />

        <Spacer className="lp-IntroTop-spacer" size="0" size768="20px" size1012="50px" />

        {isDomReady && (
          <Suspense fallback={null}>
            <IntroHero
              setCopyScrollOpacity={setCopyScrollOpacity}
              setCopyScrollScale={setCopyScrollScale}
              assetsRef={assetsRef}
            />
          </Suspense>
        )}

        <div ref={heroRef} className="lp-IntroHero">
          {heroContent ? (
            <>
              <Hero className="lp-IntroHero-hero" data-hpc align="center">
                {heroContent.fields.heading ? <Hero.Heading size="2">{heroContent.fields.heading}</Hero.Heading> : null}

                {heroContent.fields.subheading ? (
                  <Hero.Description size="300">
                    {documentToPlainTextString(heroContent.fields.subheading)}
                  </Hero.Description>
                ) : null}
              </Hero>

              {heroContent.fields.ctas ? (
                <CtaGroup contentfulContent={heroContent.fields.ctas} location="hero" />
              ) : null}
            </>
          ) : null}
        </div>

        <Spacer className="lp-IntroVisuals-spacer" size="64px" size768="560px" size1012="660px" />

        <HeroCarousel
          currentScreenIndex={currentCarouselScreenIndex}
          onAutoPlayTimeout={setCurrentCarouselScreenIndex}
          carouselAriaLabel="GitHub features"
        />
      </div>

      {heroCarouselItems ? (
        <HeroCarouselControls
          items={heroCarouselItems.map(item => ({
            label: item.fields.heading || '',
            value: item.fields.id || '',
            description: item.fields.subheading ? documentToPlainTextString(item.fields.subheading) : '',
          }))}
          currentIndex={currentCarouselScreenIndex}
          onChange={setCurrentCarouselScreenIndex}
          carouselDescriptionId="heroCarouselDescription"
        />
      ) : null}

      {logosComponent ? <ContentfulLogoSuite component={logosComponent} className="pb-7" /> : null}
    </section>
  )
}
