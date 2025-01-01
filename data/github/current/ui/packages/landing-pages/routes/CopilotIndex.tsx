import {testIdProps} from '@github-ui/test-id-props'
import {fetchVariant} from '../utils'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import {BookIcon, CopilotIcon, DeviceMobileIcon, PeopleIcon} from '@primer/octicons-react'
import {
  AnchorNav,
  AnimationProvider,
  Bento,
  Box,
  Button,
  Card,
  Footnotes,
  Grid,
  Heading,
  Hero,
  Label,
  Link,
  LogoSuite,
  River,
  RiverBreakout,
  SectionIntro,
  Stack,
  Text,
  ThemeProvider,
  Timeline,
} from '@primer/react-brand'
import resolveResponse from 'contentful-resolve-response'
import {useEffect, useRef, useState, type VideoHTMLAttributes} from 'react'

import {analyticsEvent, cohortFunnelBuilder} from '../lib/analytics'
import {Image} from '../components/Image/Image'
import {isFeatureCopilotPage, toContainerPage, toEntryCollection} from '../lib/types/contentful'
import {toPayload} from '../lib/types/payload'
import {CustomerStoryBento} from './copilot/CustomerStory'
import {CallToAction} from './copilot/CallToAction'
import {PricingCards} from './copilot/PricingCards'
import {PricingTable} from './copilot/PricingTable'
import {CopilotHeadWebGL} from './copilot/CopilotHeadWebGL'
import CopilotIconAnimation from './copilot/CopilotIconAnimation'
import {PlayIcon, PauseIcon} from './features/CopilotExtensionsIndex/CopilotIcons/CopilotIcons'

// Auto-play videos
//
// Starts playing videos when they're in view

interface VideoProps extends VideoHTMLAttributes<HTMLVideoElement> {
  src: string
  poster: string
}

function useAutoplayVideo() {
  const videoRef = useRef<HTMLVideoElement | null>(null)

  useEffect(() => {
    const currentVideoRef = videoRef.current

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            // eslint-disable-next-line github/no-then
            if (currentVideoRef) currentVideoRef.play().catch(() => {})
          } else {
            if (currentVideoRef) currentVideoRef.pause()
          }
        }
      },
      {
        threshold: 0.5, // Play once 50% of the height is...
        rootMargin: `-25% 0% -25% 0%`, // ...in the center 50% of the viewport
      },
    )

    if (currentVideoRef) {
      observer.observe(currentVideoRef)
    }

    return () => {
      if (currentVideoRef) {
        observer.unobserve(currentVideoRef)
      }
    }
  }, [])

  return videoRef
}

function AutoPlayVideo({src, poster, ...props}: VideoProps) {
  const videoRef = useAutoplayVideo()

  return (
    <video ref={videoRef} playsInline muted preload="none" poster={poster} {...props}>
      <source src={src} type="video/mp4; codecs=avc1.4d002a" />
    </video>
  )
}

export function CopilotIndex() {
  const {siteCopilotPurchaseRefresh} = useRoutePayload<{siteCopilotPurchaseRefresh: boolean}>()
  let {copilotSignupPath} = useRoutePayload<{copilotSignupPath: string}>()
  let {copilotForBusinessSignupPath} = useRoutePayload<{copilotForBusinessSignupPath: string}>()
  let {copilotForBusinessSignupPathRefresh} = useRoutePayload<{copilotForBusinessSignupPathRefresh: string}>()
  let {copilotEnterpriseSignupPath} = useRoutePayload<{copilotEnterpriseSignupPath: string}>()
  let {copilotContactSalesPath} = useRoutePayload<{copilotContactSalesPath: string}>()
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const {experimentation_copilot_signup_pricing_enabled} = useRoutePayload<{
    experimentation_copilot_signup_pricing_enabled: boolean
  }>()
  const {cft} = useRoutePayload<{cft: string}>()

  const withCft = cohortFunnelBuilder(cft)

  copilotSignupPath = withCft(copilotSignupPath, {product: 'cfi'})
  copilotForBusinessSignupPath = withCft(copilotForBusinessSignupPath, {product: 'cfb'})
  copilotForBusinessSignupPathRefresh = withCft(copilotForBusinessSignupPathRefresh, {product: 'cfb'})
  copilotEnterpriseSignupPath = withCft(copilotEnterpriseSignupPath, {product: 'ce'})
  copilotContactSalesPath = withCft(copilotContactSalesPath)
  const copilotPlansPath = withCft('/features/copilot/plans')

  const page = toContainerPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))

  // Hero Video player
  //
  // Video player with custom controls for the Hero

  const {heroVideoLg} = useRoutePayload<{heroVideoLg: string}>()
  const {heroVideoLgPoster} = useRoutePayload<{heroVideoLgPoster: string}>()
  const {heroVideoSm} = useRoutePayload<{heroVideoSm: string}>()

  const videoLgRef = useRef<HTMLVideoElement>(null)
  const videoSmRef = useRef<HTMLVideoElement>(null)
  const [videoState, setVideoState] = useState('playing')
  const [videoButtonLabel, setVideoButtonLabel] = useState('Pause')
  const [videoButtonPressed, setVideoButtonPressed] = useState(false)
  const [videoButtonAriaLabel, setVideoButtonAriaLabel] = useState(
    'GitHub Copilot Chat demo video is currently playing. Click to pause.',
  )
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)

  const azureExperimentCopilotSignupPricingExperienceUrl = '/exp/webex/variants/features_copilot_signup_pricing'

  const [pricingExperience, setPricingExperience] = useState<string>('existing_experience')

  const [isLogoSuiteAnimationPaused, setIsLogoSuiteAnimationPaused] = useState(false)
  const [logoSuiteAnimationButtonLabel, setLogoSuiteAnimationButtonLabel] = useState('Pause')
  const [logoSuiteAnimationButtonAriaLabel, setLogoSuiteAnimationButtonAriaLabel] = useState(
    'Logo suite animation is currently playing. Click to pause.',
  )
  const toggleLogoSuiteAnimationPause = () => {
    setIsLogoSuiteAnimationPaused(!isLogoSuiteAnimationPaused)
    if (isLogoSuiteAnimationPaused) {
      setLogoSuiteAnimationButtonAriaLabel('Logo suite animation is currently playing. Click to pause.')
      setLogoSuiteAnimationButtonLabel('Pause')
    } else {
      setLogoSuiteAnimationButtonAriaLabel('Logo suite animation is paused. Click to play.')
      setLogoSuiteAnimationButtonLabel('Play')
    }
  }

  const handleVideoStateChange = () => {
    if (videoState === 'playing') {
      setVideoState('paused')
      setVideoButtonLabel('Play')
      setVideoButtonPressed(true)
      setVideoButtonAriaLabel('GitHub Copilot Chat demo animation is paused. Click to play.')
      setVideoIcon(() => PlayIcon)
      if (videoLgRef.current && videoSmRef.current) {
        videoLgRef.current.pause()
        videoSmRef.current.pause()
      }
    } else if (videoState === 'paused') {
      setVideoState('playing')
      setVideoButtonLabel('Pause')
      setVideoButtonAriaLabel('GitHub Copilot Chat demo animation is currently playing. Click to pause.')
      setVideoButtonPressed(false)
      setVideoIcon(() => PauseIcon)
      if (videoLgRef.current && videoSmRef.current) {
        videoLgRef.current.play()
        videoSmRef.current.play()
      }
    } else if (videoState === 'ended') {
      setVideoState('playing')
      setVideoButtonLabel('Pause')
      setVideoButtonAriaLabel('GitHub Copilot Chat demo animation is currently playing. Click to pause.')
      setVideoButtonPressed(false)
      setVideoIcon(() => PauseIcon)
      if (videoLgRef.current && videoSmRef.current) {
        videoLgRef.current.currentTime = 0
        videoSmRef.current.currentTime = 0
        videoLgRef.current.play()
        videoSmRef.current.play()
      }
    }
  }

  const handleVideoStateEnd = () => {
    setVideoState('ended')
    setVideoButtonLabel('Replay')
    setVideoButtonAriaLabel('GitHub Copilot Chat animation has ended. Click to replay.')
    setVideoButtonPressed(true)
    setVideoIcon(() => PlayIcon)
  }

  // Pricing deep link
  //
  // This is an alternative to using `href="#pricing"` on the Hero "Compare plans" button
  // It seems deep linking currently doesn't work reliably, so we're using `scrollTo()` instead

  const ctaPricingRef = useRef<HTMLButtonElement>(null)
  const sectionPricingRef = useRef<HTMLElement>(null)

  const handlePricingClick = (event: Event) => {
    event.preventDefault()

    if (sectionPricingRef.current) {
      // Set focus to the pricing section
      sectionPricingRef.current.setAttribute('tabindex', '-1')
      sectionPricingRef.current.focus({preventScroll: true})

      // Then scroll to the pricing section
      window.scrollTo({
        top: sectionPricingRef.current.offsetTop,
      })
    }
  }

  useEffect(() => {
    const currentCtaPricingRef = ctaPricingRef.current

    if (currentCtaPricingRef) {
      currentCtaPricingRef.addEventListener('click', handlePricingClick)
    }

    return () => {
      if (currentCtaPricingRef) {
        currentCtaPricingRef.removeEventListener('click', handlePricingClick)
      }
    }
  }, [])

  useEffect(() => {
    const getPricingExperience = async () => {
      const variant = await fetchVariant(azureExperimentCopilotSignupPricingExperienceUrl, 'new_experience')

      setPricingExperience(variant)
    }

    if (experimentation_copilot_signup_pricing_enabled) {
      getPricingExperience()
    }
  }, [experimentation_copilot_signup_pricing_enabled])

  return (
    <ThemeProvider colorMode="dark" className="lp-Copilot">
      <section id="hero" className="lp-Section lp-Section--hero">
        <Grid>
          <Grid.Column span={12}>
            <Hero data-hpc align="center" className="lp-Hero">
              <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label d-inline-block mb-4">
                <Hero.Label
                  size="large"
                  leadingVisual={<CopilotIcon />}
                  color="purple-red"
                  className="lp-ConicGradientBorder-label-inner"
                  style={{height: '30px', marginBottom: '0'}}
                >
                  GitHub Copilot
                </Hero.Label>
              </div>
              <Hero.Heading size="1" weight="bold" className="lp-Hero-heading">
                The world’s most widely adopted AI developer tool
              </Hero.Heading>
              <div className="lp-Hero-ctaButtons">
                <Hero.PrimaryAction
                  href={pricingExperience === 'existing_experience' ? copilotPlansPath : '#pricing-2'}
                  className="Button--heroCta"
                  {...analyticsEvent({action: 'get_started', tag: 'button', context: 'CTAs', location: 'hero'})}
                  {...testIdProps('single-btn-copilot-plans')}
                >
                  Get started with GitHub Copilot
                </Hero.PrimaryAction>
              </div>
            </Hero>

            <Box className="lp-Hero-visual">
              <Box
                role="img"
                className="lp-Hero-videoContainer"
                aria-label="A demonstration animation of a code editor using GitHub Copilot Chat, where the user requests GitHub Copilot to generate unit tests for a given code snippet."
              >
                <video
                  autoPlay
                  playsInline
                  muted
                  className="lp-Hero-video lp-Hero-video--landscape hide-reduced-motion"
                  width="1248"
                  height="735"
                  poster={heroVideoLgPoster}
                  ref={videoLgRef}
                  onEnded={() => handleVideoStateEnd()}
                >
                  <source src={heroVideoLg} type="video/mp4; codecs=avc1.4d002a" />
                </video>

                <video
                  autoPlay
                  playsInline
                  muted
                  className="lp-Hero-video lp-Hero-video--portrait hide-reduced-motion"
                  width="539.5"
                  height="682"
                  ref={videoSmRef}
                  onEnded={() => handleVideoStateEnd()}
                >
                  <source src={heroVideoSm} type="video/mp4; codecs=avc1.4d002a" />
                </video>

                <Image
                  className="lp-Hero-videoImage hide-no-pref-motion"
                  src="/images/modules/site/copilot/hero.jpg"
                  alt="Editor with GitHub Copilot Chat"
                  width="1248"
                />
              </Box>

              <button
                className="lp-Hero-videoPlayerButton lp-pauseButton"
                onClick={handleVideoStateChange}
                aria-pressed={videoButtonPressed}
                aria-label={videoButtonAriaLabel}
                {...analyticsEvent({
                  action: videoButtonLabel.toLowerCase(),
                  tag: 'button',
                  context: 'demo_gif',
                  location: 'hero',
                })}
              >
                <VideoIcon />
                <span className="sr-only">{videoButtonLabel}</span>
              </button>

              <CopilotHeadWebGL />
            </Box>

            <LogoSuite hasDivider={false} className="lp-LogoSuite">
              <LogoSuite.Heading visuallyHidden>GitHub Copilot is used by</LogoSuite.Heading>
              <LogoSuite.Logobar marquee marqueeSpeed="slow" data-animation-paused={isLogoSuiteAnimationPaused}>
                <Image src="/images/modules/site/copilot/logos/lyft.svg" alt="Lyft" style={{height: '64px'}} />
                <Image src="/images/modules/site/copilot/logos/fedex.svg" alt="FedEx" style={{height: '37px'}} />
                <Image src="/images/modules/site/copilot/logos/atnt.svg" alt="AT&T" style={{height: '47px'}} />
                <Image src="/images/modules/site/copilot/logos/shopify.svg" alt="Shopify" style={{height: '40px'}} />
                <Image src="/images/modules/site/copilot/logos/bmw.svg" alt="BMW" style={{height: '72px'}} />
                <Image src="/images/modules/site/copilot/logos/hnm.svg" alt="H&M" style={{height: '52px'}} />
                <Image
                  src="/images/modules/site/copilot/logos/honeywell.svg"
                  alt="Honeywell"
                  style={{height: '36px'}}
                />
                <Image
                  src="/images/modules/site/copilot/logos/ey.svg"
                  alt="EY"
                  style={{height: '58px', marginTop: '-16px'}}
                />
                <Image src="/images/modules/site/copilot/logos/infosys.svg" alt="Infosys" style={{height: '36px'}} />
                <Image src="/images/modules/site/copilot/logos/bbva.svg" alt="BBVA" style={{height: '36px'}} />
              </LogoSuite.Logobar>
            </LogoSuite>

            <Box paddingBlockStart={12} className="lp-Hero-videoPlayer">
              <Button
                variant="subtle"
                hasArrow={false}
                className="lp-Hero-videoPlayerButton"
                onClick={toggleLogoSuiteAnimationPause}
                aria-pressed={isLogoSuiteAnimationPaused}
                aria-label={logoSuiteAnimationButtonAriaLabel}
                {...analyticsEvent({
                  action: logoSuiteAnimationButtonLabel.toLowerCase(),
                  tag: 'button',
                  context: 'brands',
                  location: 'hero',
                })}
              >
                {logoSuiteAnimationButtonLabel}
              </Button>
            </Box>
          </Grid.Column>
        </Grid>

        {pricingExperience === 'existing_experience' && (
          <Box style={{height: 0}}>
            <AnchorNav hideUntilSticky>
              <AnchorNav.Link
                href="#enterprise"
                {...analyticsEvent({action: 'enterprise_grade', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Enterprise-grade
              </AnchorNav.Link>
              <AnchorNav.Link
                href="#features"
                {...analyticsEvent({action: 'features', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Features
              </AnchorNav.Link>
              <AnchorNav.Link
                href="#pricing"
                {...analyticsEvent({action: 'pricing', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Pricing
              </AnchorNav.Link>
              <AnchorNav.Link
                href="#faq"
                {...analyticsEvent({action: 'faqs', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                FAQs
              </AnchorNav.Link>
              <AnchorNav.Action
                href={copilotPlansPath}
                {...analyticsEvent({
                  action: 'get_started',
                  tag: 'button',
                  context: 'sticky',
                  location: 'subnav',
                })}
              >
                Get started
              </AnchorNav.Action>
              <AnchorNav.SecondaryAction href="#" hidden />
            </AnchorNav>
          </Box>
        )}
        <div className="lp-Hero-cover" />
      </section>

      {pricingExperience === 'new_experience' && (
        <>
          <section
            id="pricing-2"
            className="lp-Section lp-Section--new-pricing-experience lp-Section--pricing"
            ref={sectionPricingRef}
          >
            <PricingCards
              siteCopilotPurchaseRefresh={siteCopilotPurchaseRefresh}
              copilotSignupPath={copilotSignupPath}
              copilotForBusinessSignupPath={copilotForBusinessSignupPath}
              copilotForBusinessSignupPathRefresh={copilotForBusinessSignupPathRefresh}
              copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
              copilotContactSalesPath={copilotContactSalesPath}
              pricingExperience={pricingExperience}
            />
          </section>
          <section className="lp-Section lp-Section--new-pricing-experience-table pt-0 pb-5">
            <details>
              <summary>
                <div style={{position: 'relative'}}>
                  <span className="icon-collapsed pr-3" />
                  <span className="icon-expanded pr-3" />
                </div>
                <h3>Compare all features</h3>
              </summary>
              <PricingTable
                copilotSignupPath={copilotSignupPath}
                copilotForBusinessSignupPath={copilotForBusinessSignupPath}
                copilotContactSalesPath={copilotContactSalesPath}
              />
            </details>
          </section>
          <Box style={{height: 0}}>
            <AnchorNav hideUntilSticky>
              <AnchorNav.Link
                href="#enterprise"
                {...analyticsEvent({action: 'enterprise_grade', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Enterprise-grade
              </AnchorNav.Link>
              <AnchorNav.Link
                href="#features"
                {...analyticsEvent({action: 'features', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Features
              </AnchorNav.Link>
              <AnchorNav.Link
                href="#faq"
                {...analyticsEvent({action: 'faqs', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                FAQs
              </AnchorNav.Link>
              <AnchorNav.Action
                href="#pricing"
                {...analyticsEvent({action: 'pricing', tag: 'link', context: 'sticky', location: 'subnav'})}
              >
                Get started with Copilot
              </AnchorNav.Action>
              <AnchorNav.SecondaryAction href="#" hidden />
            </AnchorNav>
          </Box>
        </>
      )}

      <section id="enterprise" className="lp-Section lp-Section--level-1">
        <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
          <Grid.Column span={12}>
            <SectionIntro fullWidth align="center" className="lp-SectionIntro">
              <SectionIntro.Label size="large" className="lp-Label--section">
                Enterprise-grade
              </SectionIntro.Label>
              <SectionIntro.Heading size="2" weight="semibold">
                The competitive advantage developers ask for by name
              </SectionIntro.Heading>
            </SectionIntro>
          </Grid.Column>

          <Grid.Column span={12}>
            <Bento className="Bento Bento--inset">
              <Bento.Item
                columnSpan={{xsmall: 12, medium: 6, large: 7}}
                rowSpan={{xsmall: 4, small: 3, medium: 4, large: 5, xlarge: 5}}
                visualAsBackground
              >
                <Bento.Content padding={{xsmall: 'normal', xlarge: 'spacious'}}>
                  <Bento.Heading as="h3" size="3" weight="semibold">
                    Proven to increase developer productivity and accelerate the pace of software development.
                  </Bento.Heading>
                  <Link
                    href="https://github.blog/2022-09-07-research-quantifying-github-copilots-impact-on-developer-productivity-and-happiness/"
                    size="large"
                    variant="default"
                    {...analyticsEvent({
                      action: 'research_blog',
                      tag: 'link',
                      context: 'developer_productivity',
                      location: 'enterprise_ready',
                    })}
                  >
                    Read the research
                  </Link>
                </Bento.Content>
                <Bento.Visual>
                  <Image src="/images/modules/site/copilot/enterprise-1.jpg" alt="" width="724" height="540" />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 6, large: 5}}
                rowSpan={{xsmall: 3, small: 3, medium: 4, large: 5, xlarge: 5}}
                visualAsBackground
              >
                <Bento.Content
                  padding={{xsmall: 'normal', xlarge: 'spacious'}}
                  verticalAlign="end"
                  className="lp-Bento-lastChildNoMarginBottom"
                >
                  <Bento.Heading as="h3" size="display" className="is-sansSerifAlt lp-Speed-stat">
                    55%
                  </Bento.Heading>
                  <Text as="p" size="400" weight="medium" variant="muted" style={{marginBottom: '0'}}>
                    Faster coding
                  </Text>
                </Bento.Content>
                <Bento.Visual>
                  <Image
                    src="/images/modules/site/copilot/enterprise-2.webp"
                    className="object-pos-0"
                    alt=""
                    width="492"
                    height="540"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 6, large: 5}}
                rowSpan={{xsmall: 3, small: 3, medium: 4, large: 4, xlarge: 5}}
                visualAsBackground
              >
                <Bento.Content
                  padding={{xsmall: 'normal', xlarge: 'spacious'}}
                  verticalAlign="end"
                  className="lp-Bento-lastChildNoMarginBottom"
                >
                  <Bento.Heading as="h3" size="4" weight="semibold">
                    Designed by leaders in AI so you can build with confidence.
                  </Bento.Heading>
                </Bento.Content>
                <Bento.Visual>
                  <Image
                    src="/images/modules/site/copilot/enterprise-3.webp"
                    className="object-pos-0"
                    alt=""
                    width="492"
                    height="540"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 6, large: 7}}
                rowSpan={{xsmall: 3, small: 3, medium: 4, large: 4, xlarge: 5}}
                visualAsBackground
              >
                <Bento.Content padding={{xsmall: 'normal', xlarge: 'spacious'}}>
                  <Bento.Heading as="h3" size="3" weight="semibold">
                    Committed to your privacy, security, and trust.
                  </Bento.Heading>
                  <Link
                    href="/trust-center"
                    size="large"
                    variant="default"
                    {...analyticsEvent({
                      action: 'trust_center',
                      tag: 'link',
                      context: 'privacy_tile',
                      location: 'enterprise_ready',
                    })}
                  >
                    Visit the GitHub Copilot Trust Center
                  </Link>
                </Bento.Content>
                <Bento.Visual>
                  <Image src="/images/modules/site/copilot/enterprise-4.jpg" alt="" width="724" height="540" />
                </Bento.Visual>
              </Bento.Item>

              <CustomerStoryBento />
            </Bento>
          </Grid.Column>
        </Grid>
      </section>

      <section id="productivity" className="lp-Section lp-Section--compact lp-Section--level-gradient lp-Section--illu">
        <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap lp-Section--illu-content">
          <Grid.Column span={12}>
            <SectionIntro fullWidth align="center" className="lp-SectionIntro" style={{gap: '0'}}>
              <CopilotIconAnimation />
              <SectionIntro.Heading size="3" weight="semibold">
                The industry <br className="break-whenNarrow" /> standard
              </SectionIntro.Heading>
            </SectionIntro>
          </Grid.Column>

          <Grid.Column span={12}>
            <AnimationProvider runOnce>
              <Box
                padding={32}
                className="lp-Productivity-item has-BlurredBg has-GradientBorder"
                marginBlockEnd={32}
                animate="slide-in-up"
              >
                <Image
                  src="/images/modules/site/copilot/quote.svg"
                  alt=""
                  width="44"
                  height="35"
                  className="lp-ProductivityTestimonial-quote-icon"
                />

                <Text size="600" weight="medium" className="lp-ProductivityTestimonial-quote">
                  <span className="lp-ProductivityTestimonial-quote-highlight">
                    Personalized, natural language recommendations are now at the fingertips of all our developers at
                    Figma.
                  </span>{' '}
                  Our engineers are coding faster, collaborating more effectively, and building better outcomes.
                </Text>

                <Stack
                  direction={{narrow: 'vertical', regular: 'horizontal'}}
                  gap={16}
                  padding={'none'}
                  style={{alignItems: 'center'}}
                >
                  <Image
                    src="/images/modules/site/copilot/logo-framer.svg"
                    alt=""
                    width="33"
                    height="48"
                    className="lp-ProductivityTestimonial-logo"
                  />
                  <Stack direction="vertical" gap="none" padding="none">
                    <Text as="p" weight="medium">
                      Tommy MacWilliam
                    </Text>
                    <Text as="p" weight="medium" variant="muted" className="text-mono">
                      Engineering Manager for Infrastructure @ Figma
                    </Text>
                  </Stack>
                </Stack>
              </Box>

              <Stack
                direction={{narrow: 'vertical', regular: 'horizontal'}}
                gap={32}
                padding="none"
                className="lp-Productivity"
              >
                <Box
                  padding={32}
                  className="lp-Productivity-item has-BlurredBg has-GradientBorder width-full"
                  animate="slide-in-up"
                >
                  <Heading
                    as="h3"
                    weight="medium"
                    className="is-sansSerifAlt"
                    style={{fontSize: '48px', letterSpacing: '-0.03em', lineHeight: '1'}}
                  >
                    77,000+
                  </Heading>
                  <Text as="p" weight="medium" variant="muted" style={{fontSize: '18px'}}>
                    Businesses have adopted GitHub Copilot
                  </Text>
                </Box>

                <Box
                  padding={32}
                  className="lp-Productivity-item has-BlurredBg has-GradientBorder width-full"
                  animate="slide-in-up"
                >
                  <Heading
                    as="h3"
                    weight="medium"
                    className="is-sansSerifAlt"
                    style={{fontSize: '48px', letterSpacing: '-0.03em', lineHeight: '1'}}
                  >
                    55%
                  </Heading>
                  <Text as="p" weight="medium" variant="muted" style={{fontSize: '18px'}}>
                    Developer preference for GitHub Copilot
                  </Text>
                  <Text size="100" variant="muted" style={{marginTop: '28px'}}>
                    Stack Overflow 2023 Survey
                  </Text>
                </Box>
                <Box
                  padding={32}
                  className="lp-Productivity-item has-BlurredBg has-GradientBorder width-full"
                  animate="slide-in-up"
                >
                  <Heading
                    as="h3"
                    weight="medium"
                    className="is-sansSerifAlt"
                    style={{fontSize: '48px', letterSpacing: '-0.03em', lineHeight: '1'}}
                  >
                    3B+
                  </Heading>
                  <Text as="p" weight="medium" variant="muted" style={{fontSize: '18px'}}>
                    Accepted lines of code
                    <sup>
                      <a id="footnote-ref-1-1" href="#footnote-1">
                        1
                      </a>
                    </sup>
                  </Text>
                </Box>
              </Stack>

              <Box
                padding={32}
                className="lp-Productivity-item has-BlurredBg has-GradientBorder"
                marginBlockStart={32}
                animate="slide-in-up"
                style={{alignItems: 'flex-start'}}
              >
                <Image
                  src="/images/modules/site/copilot/logo-gartner.svg"
                  alt="Gartner"
                  width="99"
                  height="23"
                  className="lp-ProductivityBox-logo"
                />

                <Text size="600" weight="medium" className="lp-ProductivityTestimonial-quote">
                  GitHub: A Leader in the 2024 Gartner® Magic Quadrant™ <br /> for AI Code Assistants
                </Text>

                <Link
                  href="https://www.gartner.com/doc/reprints?id=1-2IKO4MPE&ct=240819&st=sb"
                  variant="accent"
                  size="large"
                  target="_blank"
                  {...analyticsEvent({
                    action: 'gartner_doc',
                    tag: 'link',
                    context: 'gartner_report_copilot',
                    location: 'stats',
                  })}
                >
                  Read the report
                </Link>
              </Box>
            </AnimationProvider>
          </Grid.Column>
        </Grid>

        <Image
          src="/images/modules/site/copilot/productivity-bg.webp"
          alt=""
          width="961"
          height="691"
          className="lp-Productivity-bg"
        />
      </section>

      <section
        id="features"
        className="lp-Section lp-Section--noBottomPadding"
        style={{position: 'relative', zIndex: 1}}
      >
        <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
          <Grid.Column span={12}>
            <SectionIntro fullWidth align="center" className="lp-SectionIntro">
              <SectionIntro.Label size="large" className="lp-Label--section">
                Features
              </SectionIntro.Label>
              <SectionIntro.Heading size="2" weight="semibold">
                The AI coding assistant <br className="break-whenWide" /> elevating developer workflows
              </SectionIntro.Heading>
            </SectionIntro>
          </Grid.Column>

          <Grid.Column span={12}>
            <RiverBreakout style={{paddingTop: '0'}}>
              <a
                href="https://docs.github.com/en/copilot/github-copilot-chat/about-github-copilot-chat#use-cases-for-github-copilot-chat"
                aria-label="Accelerate workflow with interactive codebase chat"
                {...analyticsEvent({
                  action: 'chat_docs',
                  tag: 'video',
                  context: 'copilot_chat',
                  location: 'features',
                })}
              >
                <RiverBreakout.Visual aria-hidden="true" className="lp-River-visual">
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-breakout.mp4"
                    poster="/images/modules/site/copilot/features-breakout-poster.webp"
                    width="1248"
                    height="647"
                    className="d-none d-md-block hide-reduced-motion"
                    aria-label="Video demonstrating how GitHub Copilot accelerates workflow through interactive codebase chat"
                  />
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-breakout-sm.mp4"
                    poster="/images/modules/site/copilot/features-breakout-poster-sm.webp"
                    width="350"
                    height="380"
                    className="d-block d-md-none hide-reduced-motion"
                    aria-label="Video demonstrating how GitHub Copilot accelerates workflow through interactive codebase chat"
                  />
                  <Image
                    src="/images/modules/site/copilot/features-breakout.webp"
                    alt="Screenshot showing how GitHub Copilot accelerates workflow through interactive codebase chat"
                    width="1248"
                    height="647"
                    style={{display: 'block'}}
                    className="hide-no-pref-motion"
                  />
                </RiverBreakout.Visual>
              </a>
              <RiverBreakout.Content
                trailingComponent={() => (
                  <Timeline className="lp-Timeline">
                    <Timeline.Item>
                      <em>Improve code quality and security.</em> Developers feel{' '}
                      <a
                        className="lp-Link--inline"
                        href="https://github.blog/2023-10-10-research-quantifying-github-copilots-impact-on-code-quality/"
                        {...analyticsEvent({
                          action: 'code_quality_blog',
                          tag: 'link',
                          context: 'copilot_chat',
                          location: 'features',
                        })}
                      >
                        more confident in their code quality
                      </a>{' '}
                      when authoring code with GitHub Copilot. And with the built-in{' '}
                      <a
                        className="lp-Link--inline"
                        href="https://github.blog/2023-02-14-github-copilot-now-has-a-better-ai-model-and-new-capabilities/#filtering-out-security-vulnerabilities-with-a-new-ai-system"
                        {...analyticsEvent({
                          action: 'vulnerability_blog',
                          tag: 'link',
                          context: 'copilot_chat',
                          location: 'features',
                        })}
                      >
                        vulnerability prevention system
                      </a>
                      , insecure coding patterns get blocked in real time.
                    </Timeline.Item>
                    <Timeline.Item>
                      <em>Enable greater collaboration.</em> GitHub Copilot’s the newest member of your team. You can
                      ask general programming questions or very specific ones about your codebase to get answers fast,
                      learn your way around, explain a mysterious regex, or get suggestions on how to improve legacy
                      code.
                    </Timeline.Item>
                  </Timeline>
                )}
              >
                <Text className="lp-RiverBreakout-text">
                  <em>Start a conversation about your codebase.</em> Whether you’re hunting down a bug or designing a
                  new feature, turn to GitHub Copilot when you’re stuck.
                  <span style={{marginTop: '32px', marginBottom: '48px', display: 'block'}}>
                    <Link
                      href="https://docs.github.com/en/copilot/github-copilot-chat/about-github-copilot-chat#use-cases-for-github-copilot-chat"
                      variant="accent"
                      {...analyticsEvent({
                        action: 'chat_docs',
                        tag: 'link',
                        context: 'copilot_chat',
                        location: 'features',
                      })}
                    >
                      Read about use cases for GitHub Copilot Chat
                    </Link>
                  </span>
                </Text>
              </RiverBreakout.Content>
            </RiverBreakout>

            <River imageTextRatio="60:40">
              <River.Visual aria-hidden="true" className="lp-River-visual">
                <a
                  href="https://docs.github.com/en/copilot/quickstart#introduction"
                  tabIndex={-1}
                  aria-hidden="true"
                  {...analyticsEvent({
                    action: 'quickstart_docs',
                    tag: 'video',
                    context: 'ai_suggestions',
                    location: 'features',
                  })}
                >
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-river-1.mp4"
                    poster="/images/modules/site/copilot/features-river-1-poster.webp"
                    width="708"
                    height="472"
                    className="d-none d-md-block hide-reduced-motion"
                    aria-label="Video showing editor with GitHub Copilot code suggestions in real time"
                  />
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-river-1-sm.mp4"
                    poster="/images/modules/site/copilot/features-river-1-poster-sm.webp"
                    width="350"
                    height="290"
                    className="d-block d-md-none hide-reduced-motion"
                    aria-label="Video showing editor with GitHub Copilot code suggestions in real time"
                  />
                  <Image
                    src="/images/modules/site/copilot/features-river-1.webp"
                    alt="Editor with GitHub Copilot code suggestions in real time"
                    width="708"
                    height="472"
                    className="hide-no-pref-motion"
                  />
                </a>
              </River.Visual>
              <River.Content>
                <Heading as="h3" size="5">
                  Get AI-based suggestions in real time
                </Heading>
                <Text as="p" variant="muted" className="lp-River-text">
                  GitHub Copilot suggests code completions as developers type and turns natural language prompts into
                  coding suggestions based on the project&apos;s context and style conventions.
                </Text>
                <Link
                  href="https://docs.github.com/en/copilot/quickstart#introduction"
                  variant="accent"
                  {...analyticsEvent({
                    action: 'quickstart_docs',
                    tag: 'link',
                    context: 'ai_suggestions',
                    location: 'features',
                  })}
                >
                  Read the docs
                </Link>
              </River.Content>
            </River>

            <River imageTextRatio="60:40">
              <River.Visual aria-hidden="true" className="lp-River-visual">
                <a
                  href="https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot"
                  tabIndex={-1}
                  aria-hidden="true"
                  {...analyticsEvent({
                    action: 'docset_docs',
                    tag: 'video',
                    context: 'documentation',
                    location: 'features',
                  })}
                >
                  <Image
                    src="/images/modules/site/copilot/features-river-2-alt.webp?v=2"
                    alt="GitHub Copilot running custom instruction"
                    width="708"
                    height="472"
                  />
                </a>
              </River.Visual>
              <River.Content>
                <Heading as="h3" size="5">
                  <Label className="lp-Label--inRiver" style={{lineHeight: 'var(--base-size-24)'}}>
                    Technical&nbsp;Preview
                  </Label>
                  Tailor-made answers, defined by you
                </Heading>
                <Text as="p" variant="muted" className="lp-River-text">
                  Specify custom instructions to personalize chat responses in VS Code and Visual Studio based on your
                  preferred tools, organizational knowledge, and coding best practices.
                </Text>
                <Link
                  href="https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot"
                  variant="accent"
                  {...analyticsEvent({
                    action: 'docs_instructions',
                    tag: 'link',
                    context: 'documentation',
                    location: 'features',
                  })}
                >
                  Create custom instructions
                </Link>
              </River.Content>
            </River>

            <River imageTextRatio="60:40">
              <River.Visual aria-hidden="true" className="lp-River-visual">
                <a
                  href="https://github.com/features/preview/copilot-code-review"
                  tabIndex={-1}
                  aria-hidden="true"
                  {...analyticsEvent({
                    action: 'pr_review',
                    tag: 'video',
                    context: 'documentation',
                    location: 'features',
                  })}
                >
                  <Image
                    src="/images/modules/site/copilot/features-river-3-alt.webp?v=2"
                    alt="GitHub Copilot adding a review to a pull request"
                    width="708"
                    height="472"
                  />
                </a>
              </River.Visual>
              <River.Content>
                <Heading as="h3" size="5">
                  <Label className="lp-Label--inRiver" style={{lineHeight: 'var(--base-size-24)'}}>
                    Technical&nbsp;Preview
                  </Label>
                  Feedback without the wait
                </Heading>
                <Text as="p" variant="muted" className="lp-River-text">
                  Start iterating and moving towards “ready to merge” instantly. As your first stop for a code review,
                  Copilot will spot hidden bugs, tidy up spelling and grammar mistakes, level-up your error handling,
                  and more – all while you wait for a human review.
                </Text>
                <Link
                  href="https://github.com/features/preview/copilot-code-review"
                  variant="accent"
                  {...analyticsEvent({
                    action: 'pr_docs',
                    tag: 'link',
                    context: 'pull_requests',
                    location: 'features',
                  })}
                >
                  Get early access to code review
                </Link>
              </River.Content>
            </River>

            <River imageTextRatio="60:40" style={{paddingBottom: '0'}}>
              <River.Visual aria-hidden="true" className="lp-River-visual">
                <a href="https://github.com/features/copilot/extensions" tabIndex={-1} aria-hidden="true">
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-river-4.mp4"
                    poster="/images/modules/site/copilot/features-river-4-poster.webp"
                    width="708"
                    height="472"
                    className="d-none d-md-block hide-reduced-motion"
                    aria-label="Video showing GitHub Copilot chat with a list of extensions"
                  />
                  <AutoPlayVideo
                    src="/images/modules/site/copilot/features-river-4-sm.mp4"
                    poster="/images/modules/site/copilot/features-river-4-poster-sm.webp"
                    width="350"
                    height="290"
                    className="d-block d-md-none hide-reduced-motion"
                    aria-label="Video showing GitHub Copilot chat with a list of extensions"
                  />
                  <Image
                    src="/images/modules/site/copilot/features-river-4.webp"
                    alt="GitHub Copilot chat showing a list of extensions"
                    width="708"
                    height="472"
                    loading="lazy"
                    className="hide-no-pref-motion"
                  />
                </a>
              </River.Visual>
              <River.Content>
                <Heading as="h3" size="5">
                  <Label className="lp-Label--inRiver" style={{lineHeight: 'var(--base-size-24)'}}>
                    Technical&nbsp;Preview
                  </Label>
                  Your favorite tools have entered the chat
                </Heading>
                <Text as="p" variant="muted" className="lp-River-text">
                  Check log errors, create feature flags, deploy apps to the cloud. Add capabilities to GitHub Copilot
                  with an ecosystem of extensions from third-party tools and services.
                </Text>
                <Link
                  href="https://github.com/features/copilot/extensions"
                  variant="accent"
                  {...analyticsEvent({action: 'extensions', tag: 'link', context: 'tools', location: 'features'})}
                >
                  Explore GitHub Copilot Extensions
                </Link>
              </River.Content>
            </River>
          </Grid.Column>

          {/* Spacer */}
          <Box paddingBlockStart={{narrow: 96, regular: 128}} aria-hidden />

          <Grid.Column span={12}>
            <Bento className="Bento Bento--raised">
              <Bento.Item
                columnSpan={12}
                rowSpan={5}
                flow={{
                  xsmall: 'row',
                  medium: 'column',
                }}
                colorMode="dark"
                className="lp-Features-bento-5"
                style={{gridGap: 0}}
              >
                <Bento.Content
                  padding={{
                    xsmall: 'normal',
                    medium: 'spacious',
                  }}
                >
                  <Bento.Heading as="h3" size="4" weight="semibold">
                    <Label className="lp-Label--inBento">Limited Public Beta</Label>
                    Need a custom solution? <span style={{whiteSpace: 'nowrap'}}>Fine-tune</span> a private model for
                    code suggestions tailored to your practices
                  </Bento.Heading>
                  <Link
                    href="https://github.com/github-copilot/fine_tuning_waitlist_signup/join"
                    size="large"
                    variant="default"
                    {...analyticsEvent({
                      action: 'copilot_models_waitlist',
                      tag: 'link',
                      context: 'models',
                      location: 'features',
                    })}
                  >
                    Join the waitlist
                  </Link>
                </Bento.Content>
                <Bento.Visual position="16px 0" fillMedia className="lp-Features-bento-5-visual">
                  <Image
                    src="/images/modules/site/copilot/features-bento-5-visual.webp"
                    alt="Training history of a fine-tuned model for GitHub Copilot"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 7}}
                rowSpan={{xsmall: 5, medium: 5, large: 5, xlarge: 6}}
                visualAsBackground
              >
                <Bento.Content padding={{xsmall: 'normal', xlarge: 'spacious'}} verticalAlign="start">
                  <Bento.Heading as="h3" size="4" weight="semibold">
                    Ask for assistance right in your terminal
                  </Bento.Heading>
                  <Link
                    href="https://docs.github.com/copilot/github-copilot-in-the-cli"
                    size="large"
                    variant="default"
                    {...analyticsEvent({action: 'cli_docs', tag: 'link', context: 'terminal', location: 'features'})}
                  >
                    Try Copilot in the CLI
                  </Link>
                </Bento.Content>
                <Bento.Visual position="0% 50%">
                  <Image
                    src="/images/modules/site/copilot/features-bento-1-cli-ga.webp"
                    alt="Screenshot of GitHub Copilot CLI in a terminal"
                    width="724"
                    height="620"
                    className="lp-Features-bento-1-visual object-pos-left-bottom"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 5}}
                rowSpan={{xsmall: 5, medium: 5, large: 5, xlarge: 6}}
                className="Bento-item"
              >
                <Bento.Content padding={{xsmall: 'normal', xlarge: 'spacious'}} horizontalAlign="center">
                  <Bento.Heading as="h3" size="4" weight="semibold">
                    Keep flying with your favorite editor
                  </Bento.Heading>
                </Bento.Content>
                <Bento.Visual
                  padding={{xsmall: 'normal', xlarge: 'spacious'}}
                  fillMedia={false}
                  className="lp-Features-editorContainer"
                >
                  <Button
                    as="a"
                    href="https://marketplace.visualstudio.com/items?itemName=GitHub.copilot"
                    hasArrow={false}
                    className="lp-Features-editorButton"
                    {...analyticsEvent({action: 'vscode', tag: 'icon', context: 'editors', location: 'features'})}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-2-vscode.svg"
                      alt=""
                      width="90"
                      height="90"
                    />
                    <Text as="div" size="200" weight="normal">
                      VS Code
                    </Text>
                  </Button>

                  <Button
                    as="a"
                    href="https://marketplace.visualstudio.com/items?itemName=GitHub.copilotvs"
                    hasArrow={false}
                    className="lp-Features-editorButton"
                    {...analyticsEvent({action: 'vs', tag: 'icon', context: 'editors', location: 'features'})}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-2-visualstudio.svg"
                      alt=""
                      width="90"
                      height="90"
                    />
                    <Text as="div" size="200" weight="normal">
                      Visual Studio
                    </Text>
                  </Button>

                  <Button
                    as="a"
                    href="https://plugins.jetbrains.com/plugin/17718-github-copilot"
                    hasArrow={false}
                    className="lp-Features-editorButton"
                    {...analyticsEvent({action: 'jetbrains', tag: 'icon', context: 'editors', location: 'features'})}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-2-jetbrains.svg"
                      alt=""
                      width="90"
                      height="90"
                    />
                    <Text as="div" size="200" weight="normal">
                      JetBrains IDEs
                    </Text>
                  </Button>
                  <Button
                    as="a"
                    href="https://github.com/github/CopilotForXcode"
                    hasArrow={false}
                    className="lp-Features-editorButton"
                    {...analyticsEvent({action: 'xcode', tag: 'icon', context: 'editors', location: 'features'})}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-2-xcode.svg"
                      alt=""
                      width="90"
                      height="90"
                    />
                    <Text as="div" size="200" weight="normal">
                      Xcode
                    </Text>
                  </Button>
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 5, large: 5, xlarge: 5}}
                rowSpan={{xsmall: 4, small: 4, medium: 4, xlarge: 5}}
                className="Bento-item"
              >
                <Bento.Content
                  horizontalAlign={{xsmall: 'center', large: 'start'}}
                  padding={{xsmall: 'normal', xlarge: 'spacious'}}
                  leadingVisual={<DeviceMobileIcon />}
                  className="lp-Features-mobile"
                >
                  <Bento.Heading as="h3" size="4" weight="semibold" className="lp-Features-mobileText">
                    Chat with your AI pair programmer on-the-go
                  </Bento.Heading>
                </Bento.Content>
                <Bento.Visual
                  padding={{xsmall: 'normal', xlarge: 'spacious'}}
                  fillMedia={false}
                  horizontalAlign="center"
                  verticalAlign="end"
                  style={{columnGap: '24px', flexWrap: 'wrap'}}
                >
                  <a
                    href="https://play.google.com/store/apps/details?id=com.github.android"
                    {...analyticsEvent({
                      action: 'play_store',
                      tag: 'button',
                      context: 'mobile_apps',
                      location: 'features',
                    })}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-4-google.png"
                      alt="Google Play Store logo"
                      width="180"
                      height="53"
                      style={{display: 'block'}}
                    />
                  </a>
                  <a
                    href="https://apps.apple.com/app/github/id1477376905?ls=1"
                    {...analyticsEvent({
                      action: 'app_store',
                      tag: 'button',
                      context: 'mobile_apps',
                      location: 'features',
                    })}
                  >
                    <Image
                      src="/images/modules/site/copilot/features-bento-4-apple.png"
                      alt="Apple App Store logo"
                      width="179"
                      height="53"
                      style={{display: 'block'}}
                    />
                  </a>
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item
                columnSpan={{xsmall: 12, medium: 7, large: 7, xlarge: 7}}
                rowSpan={{xsmall: 4, small: 3, medium: 4, xlarge: 5}}
              >
                <Bento.Visual position="25% 0%">
                  <Image
                    src="/images/modules/site/copilot/features-bento-3-chat-ga.webp"
                    alt="A phone showing GitHub Copilot in GitHub Mobile"
                    width="724"
                    height="560"
                  />
                </Bento.Visual>
              </Bento.Item>
            </Bento>
          </Grid.Column>
        </Grid>
      </section>

      <section id="pricing" className="lp-Section lp-Section--pricing" ref={sectionPricingRef}>
        <Image
          as="picture"
          src="/images/modules/site/copilot/pricing-gradient.jpg"
          className="position-absolute top-0 left-0 width-full height-full lp-Section--pricing-gradient"
          sources={[
            {
              srcset: '/images/modules/site/copilot/pricing-gradient-sm.jpg',
              media: '(max-width: 767px)',
            },
            {
              srcset: '/images/modules/site/copilot/pricing-gradient.jpg',
              media: '(min-width: 768px) and (max-width: 1279px)',
            },
            {
              srcset: '/images/modules/site/copilot/pricing-gradient-lg.jpg',
              media: '(min-width: 1280px)',
            },
          ]}
          alt=""
        />
        <PricingCards
          siteCopilotPurchaseRefresh={siteCopilotPurchaseRefresh}
          copilotSignupPath={copilotSignupPath}
          copilotForBusinessSignupPath={copilotForBusinessSignupPath}
          copilotForBusinessSignupPathRefresh={copilotForBusinessSignupPathRefresh}
          copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
          copilotContactSalesPath={copilotContactSalesPath}
          pricingExperience={pricingExperience}
        />
      </section>

      <section className="lp-Section pt-0 pb-0">
        <PricingTable
          copilotSignupPath={copilotSignupPath}
          copilotForBusinessSignupPath={copilotForBusinessSignupPath}
          copilotContactSalesPath={copilotContactSalesPath}
        />

        <div className="mt-8 mb-lg-8">
          <CallToAction copilotContactSalesPath={copilotContactSalesPath} />
        </div>
      </section>

      <section id="resources" className="lp-Section lp-Section--compact">
        <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
          <Grid.Column span={12}>
            <SectionIntro fullWidth align="center" className="lp-SectionIntro">
              <SectionIntro.Heading size="3" weight="semibold">
                Get the most out of GitHub Copilot
              </SectionIntro.Heading>
            </SectionIntro>

            <Stack
              direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
              gap="normal"
              padding="none"
            >
              <div className="lp-Resources-card">
                <Card
                  ctaText="Explore GitHub Expert Services"
                  href="https://github.com/services/"
                  {...analyticsEvent({
                    action: 'services',
                    tag: 'link',
                    context: 'consulting_card',
                    location: 'additional_resources',
                  })}
                >
                  <Card.Icon icon={<PeopleIcon />} color="purple" hasBackground />
                  <Card.Heading>Hands-on consulting, guided workshops, and training</Card.Heading>
                  <Card.Description>
                    Insights, best practices, and knowledge to help you adopt GitHub quickly and efficiently.
                  </Card.Description>
                </Card>
              </div>

              <div className="lp-Resources-card">
                <Card
                  ctaText="Read customer stories"
                  href="https://github.com/customer-stories"
                  {...analyticsEvent({
                    action: 'stories',
                    tag: 'link',
                    context: 'meet_companies_card',
                    location: 'additional_resources',
                  })}
                >
                  <Card.Icon icon={<BookIcon />} color="purple" hasBackground />
                  <Card.Heading>Meet the companies who build with GitHub</Card.Heading>
                  <Card.Description>
                    Leading organizations choose GitHub to plan, build, secure and ship software.
                  </Card.Description>
                </Card>
              </div>

              <div className="lp-Resources-card">
                <Card
                  ctaText="Read blog"
                  href="https://github.blog/"
                  {...analyticsEvent({
                    action: 'blog',
                    tag: 'link',
                    context: 'latest_trends_card',
                    location: 'additional_resources',
                  })}
                >
                  <Card.Icon icon={<BookIcon />} color="purple" hasBackground />
                  <Card.Heading>Keep up with the latest on GitHub and trends in AI</Card.Heading>
                  <Card.Description>
                    Check out the GitHub blog for tips, technical guides, best practices, and more.
                  </Card.Description>
                </Card>
              </div>
            </Stack>
          </Grid.Column>
        </Grid>
      </section>

      {/* FAQGroup content is managed through Contentful: */}
      {isFeatureCopilotPage(page) && (
        <section id="faq" className="lp-Section lp-Section--level-1">
          <Grid>
            <Grid.Column span={12} className="lp-FAQs">
              <ContentfulFaqGroup component={page.fields.template.fields.faqGroup} />
            </Grid.Column>
          </Grid>
        </section>
      )}

      <section
        id="footnotes"
        className="lp-Section lp-Section--level-1 lp-Section--footnotes"
        style={{paddingTop: '0'}}
      >
        <Grid className="lp-Grid--noRowGap">
          <Grid.Column span={12}>
            <Footnotes>
              <Footnotes.Item id="footnote-1" href="#footnote-ref-1-1">
                Data from June 2023. Additional research can be found{' '}
                <a
                  className="lp-Link--inline"
                  href="https://github.blog/news-insights/research/the-economic-impact-of-the-ai-powered-developer-lifecycle-and-lessons-from-github-copilot/"
                  {...analyticsEvent({
                    action: 'copilot_usage_data',
                    tag: 'link',
                    context: 'footnote',
                    location: 'features_table',
                  })}
                >
                  here
                </a>
                .
              </Footnotes.Item>

              <Footnotes.Item id="footnote-2" href="#footnote-ref-2-1">
                Feature in public beta for Copilot Individual and Business plans. Requires use of repositories, issues,
                discussions, Actions, and other features of GitHub.
              </Footnotes.Item>

              <Footnotes.Item id="footnote-3" href="#footnote-ref-3-1">
                <a
                  className="lp-Link--inline"
                  href="https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-saml-single-sign-on/about-authentication-with-saml-single-sign-on"
                  {...analyticsEvent({
                    action: 'saml_sso',
                    tag: 'link',
                    context: 'footnote',
                    location: 'features_table',
                  })}
                >
                  Authentication with SAML single sign-on (SSO)
                </a>{' '}
                available for organizations using GitHub Enterprise Cloud.
              </Footnotes.Item>
            </Footnotes>
          </Grid.Column>
        </Grid>
      </section>
    </ThemeProvider>
  )
}
