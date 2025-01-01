import {useRef, useState, lazy, Suspense} from 'react'
import {Hero} from '@primer/react-brand'

//import IntroHero from './IntroHero'
import {Spacer} from './_shared'
import HeroCarousel from './components/HeroCarousel/HeroCarousel'
import HeroCarouselControls, {
  type HeroCarouselControlsProps,
} from './components/HeroCarousel/HeroCarouselControls/HeroCarouselControls'
import CtaForm from './components/CtaForm/CtaForm'
import Logos from './components/Logos/Logos'
import {COPY} from './Intro.data'
import type Assets from './webgl-utils/assets'
import {useDomReady} from '../../lib/utils/platform'

const IntroHero = lazy(() => import('./IntroHero'))

export default function Intro({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
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

        {/* Hero */}
        <div ref={heroRef} className="lp-IntroHero">
          <Hero className="lp-IntroHero-hero" data-hpc align="center">
            <Hero.Heading size="2">{COPY.hero.heading}</Hero.Heading>
            <Hero.Description size="300">{COPY.hero.description}</Hero.Description>
          </Hero>
          <CtaForm location="hero" />
        </div>

        <Spacer className="lp-IntroVisuals-spacer" size="64px" size768="560px" size1012="660px" />

        {/* Carousel */}
        <HeroCarousel
          isVisible
          currentScreenIndex={currentCarouselScreenIndex}
          onAutoPlayTimeout={setCurrentCarouselScreenIndex}
          carouselAriaLabel={COPY.carousel.aria.label}
          playButtonAriaLabel={COPY.carousel.aria.playButton}
        />
      </div>

      {/* Carousel controls */}
      <HeroCarouselControls
        items={COPY.carousel.items as HeroCarouselControlsProps['items']}
        currentIndex={currentCarouselScreenIndex}
        onChange={setCurrentCarouselScreenIndex}
        carouselDescriptionId={COPY.carousel.aria.descriptionId}
      />

      {/* Logos */}
      <Logos />
    </section>
  )
}
