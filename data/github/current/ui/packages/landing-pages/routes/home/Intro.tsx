import {useRef, useState, useEffect, lazy} from 'react'
import {Hero, LogoSuite, Image} from '@primer/react-brand'

//import IntroHero from './IntroHero'
import {LOGOS} from './IntroLogos.data'
import {Spacer} from './_shared'
import HeroCarousel from './components/HeroCarousel/HeroCarousel'
import HeroCarouselControls, {
  type HeroCarouselControlsProps,
} from './components/HeroCarousel/HeroCarouselControls/HeroCarouselControls'
import CtaForm from './components/CtaForm/CtaForm'
import {COPY} from './Intro.data'
import type Assets from './webgl-utils/assets'

const IntroHero = lazy(() => import('./IntroHero'))

export default function Intro({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
  const [currentCarouselScreenIndex, setCurrentCarouselScreenIndex] = useState<number>(0)
  const heroRef = useRef<HTMLDivElement | null>(null)
  const [isDomReady, setIsDomReady] = useState(false)

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

  useEffect(() => {
    if (isDomReady) return

    const onDomReady = () => {
      setIsDomReady(true)
    }

    if (document.readyState === 'complete') {
      onDomReady()
    } else {
      window.addEventListener('load', onDomReady)
    }

    return () => {
      window.removeEventListener('load', onDomReady)
    }
  })

  return (
    <section id="hero">
      <div className="lp-Intro">
        {/* Header 72 + Global Banner 42 = 114px */}
        <Spacer size="114px" />
        <Spacer size="0" size768="20px" size1012="50px" />
        {isDomReady && (
          <IntroHero
            setCopyScrollOpacity={setCopyScrollOpacity}
            setCopyScrollScale={setCopyScrollScale}
            assetsRef={assetsRef}
          />
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
          playButtonAriaLabel={COPY.carousel.aria.playButton}
        />
      </div>

      {/* Carousel controls */}
      <HeroCarouselControls
        items={COPY.carousel.items as HeroCarouselControlsProps['items']}
        currentIndex={currentCarouselScreenIndex}
        onChange={setCurrentCarouselScreenIndex}
        toggleAriaLabel={COPY.carousel.aria.controlsToggle}
      />

      {/* Logos */}
      <LogoSuite className="IntroLogoSuite">
        <LogoSuite.Heading visuallyHidden>{COPY.logoSuite.heading}</LogoSuite.Heading>
        <LogoSuite.Logobar marquee marqueeSpeed="slow">
          {LOGOS.map((logo, index) => (
            <Image
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              src={logo.image}
              alt={logo.alt}
              style={{width: logo.width, height: 'auto'}}
              loading="lazy"
            />
          ))}
        </LogoSuite.Logobar>
      </LogoSuite>
    </section>
  )
}
