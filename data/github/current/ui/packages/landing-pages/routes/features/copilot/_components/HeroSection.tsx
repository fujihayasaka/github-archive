import {testIdProps} from '@github-ui/test-id-props'
import {useCallback, useEffect, useRef, useState, lazy, Suspense} from 'react'
import {CopilotIcon} from '@primer/octicons-react'
import {Box, Grid, Hero} from '@primer/react-brand'
import CopilotSubNav from './CopilotSubNav'
import {PlayIcon, PauseIcon} from '../extensions/components/CopilotIcons/CopilotIcons'
import {usePrefersReducedMotion} from '../../../../lib/utils/platform'
import {analyticsEvent} from '../../../../lib/analytics'
import VSCodeCta from './VSCodeCta'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'
import type {PrimerComponentSubnav} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSubnav'

import heroVideoLg from '../_assets/hero-lg.mp4'
import heroVideoSm from '../_assets/hero-sm.mp4'
import heroVideoLgPoster from '../_assets/hero-poster.webp'
import LogoSuiteSection from './LogoSuiteSection'
import heroBgSm from '../_assets/hero-bg-sm.jpg'
import heroBg from '../_assets/hero-bg.jpg'
import heroBgLg from '../_assets/hero-bg-lg.webp'

const CopilotHeadWebGL = lazy(() => import('./CopilotHeadWebGL'))

interface HeroSectionProps {
  copilotProSignupPath?: string
  copilotPlansPath: string
  subnav?: PrimerComponentSubnav
}

export default function HeroSection({copilotPlansPath, subnav}: HeroSectionProps) {
  // Hero Video player
  //
  // Video player with custom controls for the Hero
  const isReducedMotion = usePrefersReducedMotion()

  const heroVideoPlayerCopy = {
    label: {
      play: 'Play',
      pause: 'Pause',
      replay: 'Replay',
    },
    ariaLabel: {
      play: 'GitHub Copilot Chat demo video is currently paused. Click to play.',
      pause: 'GitHub Copilot Chat demo video is currently playing. Click to pause.',
      replay: 'GitHub Copilot Chat demo video has ended. Click to replay.',
    },
  }

  const videoLgRef = useRef<HTMLVideoElement>(null)
  const videoSmRef = useRef<HTMLVideoElement>(null)
  const [videoState, setVideoState] = useState('playing')
  const [videoButtonLabel, setVideoButtonLabel] = useState(heroVideoPlayerCopy.label.pause)
  const [videoButtonPressed, setVideoButtonPressed] = useState(false)
  const [videoButtonAriaLabel, setVideoButtonAriaLabel] = useState(heroVideoPlayerCopy.ariaLabel.pause)
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)

  const setPausedButtonState = useCallback(() => {
    setVideoState('paused')
    setVideoButtonLabel(heroVideoPlayerCopy.label.play)
    setVideoButtonPressed(true)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.play)
    setVideoIcon(() => PlayIcon)
  }, [heroVideoPlayerCopy.ariaLabel.play, heroVideoPlayerCopy.label.play])

  const setPlayingButtonState = useCallback(() => {
    setVideoState('playing')
    setVideoButtonLabel(heroVideoPlayerCopy.label.pause)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.pause)
    setVideoButtonPressed(false)
    setVideoIcon(() => PauseIcon)
  }, [heroVideoPlayerCopy.ariaLabel.pause, heroVideoPlayerCopy.label.pause])

  const setReplayButtonState = () => {
    setVideoState('ended')
    setVideoButtonLabel(heroVideoPlayerCopy.label.replay)
    setVideoButtonAriaLabel(heroVideoPlayerCopy.ariaLabel.replay)
    setVideoButtonPressed(true)
    setVideoIcon(() => PlayIcon)
  }

  const introVideoPlay = () => {
    const playPromiseLg = videoLgRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromiseLg !== undefined) playPromiseLg.catch(() => {})

    const playPromiseSm = videoSmRef.current?.play()
    // eslint-disable-next-line github/no-then
    if (playPromiseSm !== undefined) playPromiseSm.catch(() => {})
  }

  const introVideoPause = () => {
    videoLgRef.current?.pause()
    videoSmRef.current?.pause()
  }

  const handleVideoStateChange = () => {
    if (!videoLgRef.current || !videoSmRef.current) return

    if (videoState === 'playing') {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    if (videoState === 'ended') {
      videoLgRef.current.currentTime = 0
      videoSmRef.current.currentTime = 0
    }

    introVideoPlay()
  }

  // On reduced motion change
  useEffect(() => {
    if (!videoLgRef.current || !videoSmRef.current) return

    if (isReducedMotion) {
      setPausedButtonState()
      introVideoPause()
      return
    }

    setPlayingButtonState()
    introVideoPlay()
  }, [isReducedMotion, setPausedButtonState, setPlayingButtonState])

  return (
    <div className="position-relative">
      <Box className="lp-SubNav-spacer" />
      {subnav ? (
        <ContentfulSubnav component={subnav} className="lp-Hero-subnav lp-Hero-subnav--highContrast" />
      ) : (
        <CopilotSubNav currentUrl="/features/copilot" />
      )}

      <Box className="lp-Section--hero-bg-wrap">
        <img
          src={heroBgSm}
          srcSet={`
            ${heroBgSm} 543w,
            ${heroBg} 1279w,
            ${heroBgLg} 1280w
          `}
          sizes="
            (max-width: 543px) 100vw,
            (min-width: 544px) and (max-width: 1279px) 100vw,
            (min-width: 1280px) 2400px
          "
          alt=""
          aria-hidden="true"
          className="lp-Section--hero-bg"
        />
      </Box>

      <section id="hero" className="lp-Section lp-Section--compact lp-Section--hero">
        <Grid>
          <Grid.Column span={12}>
            <Hero data-hpc align="center" className="lp-Hero">
              <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label lp-ConicGradientBorder-hero d-inline-block mb-4">
                <Hero.Label
                  size="large"
                  leadingVisual={<CopilotIcon />}
                  color="purple-red"
                  className="lp-ConicGradientBorder-label-inner"
                  style={{minHeight: '30px', height: 'auto', marginBottom: '0'}}
                >
                  GitHub Copilot is now available for free
                </Hero.Label>
              </div>
              <Hero.Heading size="1" weight="bold" className="lp-Hero-heading lp-Hero-heading-mask">
                The AI editor for everyone
              </Hero.Heading>
              <div className="lp-Hero-ctaButtons">
                <Hero.PrimaryAction
                  href="https://github.com/copilot"
                  hasArrow={false}
                  {...analyticsEvent({action: 'start_free', tag: 'button', context: 'CTAs', location: 'hero'})}
                  {...testIdProps('primary-btn-copilot-start-free')}
                >
                  Get started for free
                </Hero.PrimaryAction>

                <Hero.SecondaryAction
                  href={copilotPlansPath}
                  className="Button--heroCta"
                  hasArrow={false}
                  {...analyticsEvent({action: 'see_plans', tag: 'button', context: 'CTAs', location: 'hero'})}
                  {...testIdProps('secondary-btn-copilot-plans')}
                >
                  See plans & pricing
                </Hero.SecondaryAction>
              </div>
              <VSCodeCta />
            </Hero>

            <Box className="lp-Hero-visual">
              <Box
                role="img"
                className="lp-Hero-videoContainer"
                aria-label="A demonstration animation of a code editor using GitHub Copilot Chat, where the user requests GitHub Copilot to generate unit tests for a given code snippet."
              >
                <video
                  playsInline
                  muted
                  className="lp-Hero-video lp-Hero-video--landscape"
                  width="1248"
                  height="735"
                  poster={heroVideoLgPoster}
                  ref={videoLgRef}
                  onEnded={() => setReplayButtonState()}
                >
                  <source src={heroVideoLg} type="video/mp4; codecs=avc1.4d002a" />
                </video>

                <video
                  playsInline
                  muted
                  className="lp-Hero-video lp-Hero-video--portrait"
                  width="539.5"
                  height="682"
                  ref={videoSmRef}
                  poster={heroVideoLgPoster}
                  onEnded={() => setReplayButtonState()}
                >
                  <source src={heroVideoSm} type="video/mp4; codecs=avc1.4d002a" />
                </video>
              </Box>

              <button
                className="lp-Hero-videoPlayerButton PlayButton PlayButton--gray"
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
              <Suspense>
                <CopilotHeadWebGL />
              </Suspense>
            </Box>

            <LogoSuiteSection />
            <Box className="lp-Hero-fade">
              <svg
                width="1600"
                height="502"
                aria-hidden="true"
                style={{width: '100%', height: 'auto', display: 'block'}}
              />
            </Box>
          </Grid.Column>
        </Grid>

        {/* <AnchorNavSection copilotPlansPath={copilotPlansPath} /> */}
        <div className="lp-Hero-cover" />
      </section>
    </div>
  )
}
