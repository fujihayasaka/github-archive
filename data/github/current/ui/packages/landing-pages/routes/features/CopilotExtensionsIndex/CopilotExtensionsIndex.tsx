import {useCallback, useEffect, useRef, useState} from 'react'
import {
  ThemeProvider,
  Hero,
  SectionIntro,
  River,
  Heading,
  Image,
  Text,
  Testimonial,
  CTABanner,
  Button,
  Grid,
  Card,
  Link,
  FAQ,
  SubNav,
} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

import CopilotExtensionsHeroUI from './CopilotExtensionsHeroUI/CopilotExtensionsHeroUI'
import {COPY, HERO_EXTENSIONS, type CardData} from './CopilotExtensionsIndex.data'
import {SUBNAV_LINKS} from '../../copilot/SubNav.data'
import {PlayIcon, PauseIcon, CopilotIcon} from './CopilotIcons/CopilotIcons'

export function CopilotExtensionsIndex() {
  const [playStates, setPlayStates] = useState<Record<'hero' | 'ctaBanner', boolean>>({hero: true, ctaBanner: true})
  const playButtonRefs = useRef<Record<'hero' | 'ctaBanner', HTMLButtonElement | null>>({hero: null, ctaBanner: null})

  const getCards = useCallback((cards: CardData[]) => {
    return cards.map((card, index) => {
      const CardIcon = <card.icon />
      return (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <Grid.Column key={`card_${index}`} className="lp-GridColumn" span={{xsmall: 12, medium: 6, large: 4}}>
          <Card className="lp-Card" ctaText={card.cta.label} href={card.cta.url}>
            <Card.Icon className="lp-Card-icon" icon={CardIcon} color="purple" size="medium" />
            <Card.Heading size="6">{card.title}</Card.Heading>
            <Card.Description>{card.description}</Card.Description>
          </Card>
        </Grid.Column>
      )
    })
  }, [])

  const getPauseButtonDOM = useCallback(
    (scene: 'hero' | 'ctaBanner') => (
      <button
        aria-label={COPY.aria.togglePlayButton[playStates[scene] ? 'pause' : 'play']}
        ref={ref => {
          if (ref) playButtonRefs.current[scene] = ref
        }}
        className={`lp-pauseButton lp-pauseButton--${scene} ${
          scene === 'hero' ? 'js-hero-pause-button' : 'js-cta-pause-button'
        }`}
      >
        {playStates[scene] ? (
          <PauseIcon ariaLabel={COPY.aria.togglePlayButton.pause} />
        ) : (
          <PlayIcon ariaLabel={COPY.aria.togglePlayButton.play} />
        )}
      </button>
    ),
    [playStates],
  )

  useEffect(() => {
    // Syncs the state with the WebGL-assigned class as the source of truth
    const observers: MutationObserver[] = []

    for (const playButtonRef of Object.entries(playButtonRefs.current)) {
      const [scene, element] = playButtonRef
      if (!element) return

      const observer = new MutationObserver(([entry]) => {
        if (!entry?.target) return

        setPlayStates(prevStates => ({
          ...prevStates,
          [scene]: !(entry.target as HTMLElement).classList.contains('isPaused'),
        }))
      })

      observer.observe(element, {
        attributeFilter: ['class'],
      })

      observers.push(observer)
    }

    return () => {
      for (const observer of observers) {
        observer.disconnect()
      }
    }
  }, [])

  return (
    <ThemeProvider colorMode="dark" className="fp-hasFontSmoothing">
      {/* Hero */}
      <section id="hero">
        {/* Header 72px */}
        <Spacer size="66px" size768="72px" />
        <SubNav className="lp-Hero-subnav">
          <SubNav.Heading
            href={SUBNAV_LINKS.logo.url}
            className="d-block mr-3 mr-lg-4 position-relative lp-Hero-subnav-heading"
          >
            {SUBNAV_LINKS.logo.label}
            <Text className="lp-Hero-subnav-separator" size="300" weight="semibold" aria-hidden="true">
              /
            </Text>
          </SubNav.Heading>
          {SUBNAV_LINKS.items.map((item, index) => (
            <SubNav.Link
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`subnav_${index}`}
              href={index ? item.url : '#'}
              className={!index ? 'selected' : ''}
              aria-current={!index ? 'page' : undefined}
            >
              {item.label}
            </SubNav.Link>
          ))}
        </SubNav>

        <Spacer size="72px" size768="128px" />

        <div className="lp-Hero-bg js-hero-bg">
          <canvas className="lp-Hero-bg-canvas" />
        </div>
        <div className="fp-Section-container lp-Hero-container">
          <Hero data-hpc align="center" className="fp-Hero">
            <Hero.Heading size="2" className="lp-Hero-heading">
              {COPY.hero.title}
            </Hero.Heading>
            <Hero.PrimaryAction className="lp-Hero-cta lp-Hero-cta--1 js-hero-cta" href={COPY.hero.cta1.url}>
              {COPY.hero.cta1.label}
            </Hero.PrimaryAction>
            <Hero.SecondaryAction className="lp-Hero-cta lp-Hero-cta--2 js-hero-cta" href={COPY.hero.cta2.url}>
              {COPY.hero.cta2.label}
            </Hero.SecondaryAction>
          </Hero>

          <Spacer size="64px" size768="80px" />

          <CopilotExtensionsHeroUI />

          <div className="lp-Hero-pauseButtonContainer">
            <Spacer size="128px" size768="80px" />
            {getPauseButtonDOM('hero')}
          </div>

          <Text
            size="400"
            weight="medium"
            className="lp-Hero-description"
            // eslint-disable-next-line react/forbid-component-props
            dangerouslySetInnerHTML={{__html: COPY.hero.description}}
          />

          <div className="lp-Hero-logos">
            <ul className="lp-Hero-extensions">
              {HERO_EXTENSIONS.slice(0, 5).map((extension, index) => (
                // eslint-disable-next-line @eslint-react/no-array-index-key
                <li key={`extension_${index}`} className="lp-Hero-extensionLogo">
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
                // eslint-disable-next-line @eslint-react/no-array-index-key
                <li key={`extension_${index}`} className="lp-Hero-extensionLogo">
                  <Image src={extension.image} alt={extension.alt} />
                </li>
              ))}
            </ul>
          </div>

          {/* Account for logo block height */}
          <Spacer size="32px" size768="64px" />
          <Spacer size="84px" size768="104px" />
        </div>
      </section>

      {/* Features */}
      <section id="features">
        <div className="fp-Section-container">
          <Spacer size="96px" size768="128px" />

          <SectionIntro className="fp-SectionIntro" fullWidth>
            <SectionIntro.Label className="fp-SectionIntro-label">{COPY.features.label}</SectionIntro.Label>
            <SectionIntro.Heading
              size="3"
              // eslint-disable-next-line react/forbid-component-props
              dangerouslySetInnerHTML={{__html: COPY.features.title}}
            />
          </SectionIntro>

          <Spacer size="80px" size768="112px" />

          {COPY.features.items.map((item, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <River key={`river_${index}`} className="lp-River" imageTextRatio="60:40">
              <River.Visual className="fp-River-visual lp-River-visual">
                <Image src={item.image.url} alt={item.image.alt} />
              </River.Visual>
              <River.Content>
                <Heading as="h3" size="5">
                  {item.title}
                </Heading>
                <Text>{item.description}</Text>
                {item.link ? (
                  <Link variant="accent" href={item.link.url}>
                    {item.link.label}
                  </Link>
                ) : (
                  <></>
                )}
              </River.Content>
            </River>
          ))}
        </div>
      </section>

      {/* Testimonials */}
      <section id="testimonials" className="lp-Testimonials">
        <div className="fp-Section-container lp-TestimonialsContainer">
          <Spacer size="96px" size768="128px" />

          <Image
            className="lp-TestimonialsVisual lp-TestimonialsVisual--1"
            src="/images/modules/site/copilot/extensions/testimonial-bg-1.webp"
            width={414}
            alt=""
          />
          <Image
            className="lp-TestimonialsVisual lp-TestimonialsVisual--2"
            src="/images/modules/site/copilot/extensions/testimonial-bg-2.webp"
            width={588}
            alt=""
          />

          <Testimonial quoteMarkColor="default" size="large" className="lp-Testimonial">
            <Testimonial.Quote className="lp-TestimonialQuote">
              {/* eslint-disable-next-line react/no-danger */}
              <span dangerouslySetInnerHTML={{__html: COPY.testimonial.quote}} />
            </Testimonial.Quote>
            <Testimonial.Name position={COPY.testimonial.position}>{COPY.testimonial.name}</Testimonial.Name>
          </Testimonial>
        </div>
      </section>

      {/* Get started */}
      <section id="resources">
        <div className="fp-Section-container">
          <Spacer size="96px" size768="128px" />

          <SectionIntro className="fp-SectionIntro" fullWidth>
            <SectionIntro.Label className="fp-SectionIntro-label">{COPY.getStarted.label}</SectionIntro.Label>
            <SectionIntro.Heading
              size="3"
              // eslint-disable-next-line react/forbid-component-props
              dangerouslySetInnerHTML={{__html: COPY.getStarted.title}}
            />
          </SectionIntro>

          <Spacer size="80px" size768="80px" />

          <Grid className="lp-Grid">{getCards(COPY.getStarted.cards)}</Grid>
        </div>
      </section>

      {/* CTA */}
      <section id="cta">
        <div className="fp-Section-container">
          <Spacer size="160px" size768="192px" />

          <CTABanner className="lp-CTABanner js-cta-banner" align="center" hasShadow={false}>
            <canvas className="lp-CTABanner-background js-cta-background" />
            <canvas className="lp-CTABanner-copilot js-copilot-head" aria-label={COPY.ctaBanner.aria.copilotHead} />
            {getPauseButtonDOM('ctaBanner')}
            <CTABanner.Heading size="2">{COPY.ctaBanner.title}</CTABanner.Heading>
            <CTABanner.ButtonGroup buttonsAs="a">
              <Button href={COPY.ctaBanner.cta1.url}>{COPY.ctaBanner.cta1.label}</Button>
              <Button href={COPY.ctaBanner.cta2.url}>{COPY.ctaBanner.cta2.label}</Button>
            </CTABanner.ButtonGroup>
          </CTABanner>
        </div>
      </section>

      {/* Additional resources */}
      <section id="additional-resources">
        <div className="fp-Section-container">
          <Spacer size="96px" size768="128px" />

          <SectionIntro className="fp-SectionIntro fp-SectionIntro--resources" fullWidth>
            <SectionIntro.Heading
              as="h2"
              size="3"
              // eslint-disable-next-line react/forbid-component-props
              dangerouslySetInnerHTML={{__html: COPY.resources.title}}
            />
          </SectionIntro>

          <Spacer size="40px" size768="80px" />

          <Grid className="lp-Grid">{getCards(COPY.resources.cards)}</Grid>
        </div>
      </section>

      {/* FAQs */}
      <section id="faq">
        <div className="fp-Section-container">
          <Spacer size="96px" size768="128px" />

          <FAQ className="lp-Faq">
            <FAQ.Heading as="h2">{COPY.faq.title}</FAQ.Heading>
            {COPY.faq.items.map((item, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <FAQ.Item key={`item_${index}`}>
                <FAQ.Question as="h3">{item.question}</FAQ.Question>
                <FAQ.Answer>
                  {item.answer.map((answer, i) => (
                    // eslint-disable-next-line react/no-danger, @eslint-react/no-array-index-key
                    <p key={`item_answer_${i}`} dangerouslySetInnerHTML={{__html: answer}} />
                  ))}
                </FAQ.Answer>
              </FAQ.Item>
            ))}
          </FAQ>

          <Spacer size="96px" size768="128px" />
        </div>
      </section>
    </ThemeProvider>
  )
}
