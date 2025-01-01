import {Hero as PrimerHero, Text, Image, useWindowSize, BreakpointSize} from '@primer/react-brand'
import {useMemo, useRef} from 'react'

import CopilotSubNav from '../../../../_components/CopilotSubNav'
import {Spacer} from '../../../../../components/Spacer'
import {COPY, HERO_EXTENSIONS} from '../../../Index.data'
import {CopilotIcon} from '../../CopilotIcons/CopilotIcons'

import HeroUI from './HeroUI/HeroUI'
import useIntersectionObserver from '../../../../../../../lib/hooks/useIntersectionObserver'

interface HeroProps {}

const defaultProps: Partial<HeroProps> = {}

const Hero: React.FC<HeroProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const logosContainerRef = useRef<HTMLDivElement>(null)

  const windowSize = useWindowSize()
  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )
  const {isIntersecting: isLogosContainerInView} = useIntersectionObserver(
    logosContainerRef,
    {
      threshold: {mobile: 0.2, desktop: 0.6},
      isOnce: true,
    },
    isDesktopView,
  )

  return (
    <section id="hero">
      {/* Header 72px */}
      <Spacer size="66px" size768="72px" />

      <CopilotSubNav currentUrl="/features/copilot/extensions" />

      <Spacer size="72px" size768="128px" />

      <div className="lp-Hero-bg js-hero-bg">
        <canvas className="lp-Hero-bg-canvas lp-Hero-bg-canvas--loading" />
      </div>
      <div className="fp-Section-container lp-Hero-container">
        <PrimerHero data-hpc align="center" className="fp-Hero">
          <PrimerHero.Heading size="2" className="lp-Hero-heading">
            {COPY.hero.title}
          </PrimerHero.Heading>
          <PrimerHero.PrimaryAction className="lp-Hero-cta lp-Hero-cta--1 js-hero-cta" href={COPY.hero.cta1.url}>
            {COPY.hero.cta1.label}
          </PrimerHero.PrimaryAction>
          <PrimerHero.SecondaryAction className="lp-Hero-cta lp-Hero-cta--2 js-hero-cta" href={COPY.hero.cta2.url}>
            {COPY.hero.cta2.label}
          </PrimerHero.SecondaryAction>
        </PrimerHero>

        <Spacer size="64px" size768="80px" />
        <HeroUI />
        <Spacer size="128px" size768="80px" />
        <Text
          size="400"
          weight="medium"
          className="lp-Hero-description"
          // eslint-disable-next-line react/forbid-component-props
          dangerouslySetInnerHTML={{__html: COPY.hero.description}}
        />

        <div
          ref={logosContainerRef}
          className={`lp-Hero-logos ${!isLogosContainerInView ? 'lp-Hero-logos--hidden' : ''}`}
        >
          <ul className="lp-Hero-extensions">
            {HERO_EXTENSIONS.slice(0, 5).map((extension, index, array) => (
              <li
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`extension_${index}`}
                className="lp-Hero-extensionLogo lp-Hero-extensionLogo--left"
                style={{'--staggerIndex': array.length - 1 - index}}
              >
                <Image src={extension.image} alt={extension.alt} />
              </li>
            ))}
          </ul>
          <div className="lp-Hero-copilotLogo">
            <div>
              <CopilotIcon ariaLabel={COPY.hero.extensions.aria.copilotLogo} />
            </div>
          </div>
          <ul className="lp-Hero-extensions">
            {HERO_EXTENSIONS.slice(5, 10).map((extension, index) => (
              <li
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`extension_${index}`}
                className="lp-Hero-extensionLogo lp-Hero-extensionLogo--right"
                style={{'--staggerIndex': index}}
              >
                <Image src={extension.image} alt={extension.alt} />
              </li>
            ))}
          </ul>
        </div>

        {/* Account for logo block height */}
        <Spacer size="32px" size768="64px" />
        <Spacer size="104px" size768="160px" />
      </div>
    </section>
  )
}

export default Hero
