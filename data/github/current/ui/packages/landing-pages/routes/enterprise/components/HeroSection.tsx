import {useEffect, useRef} from 'react'
import {Hero, EyebrowBanner, LogoSuite, Image, Box} from '@primer/react-brand'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import EnterpriseSubNav from '../shared/SubNav'

export default function HeroSection() {
  const videoLgRef = useRef<HTMLVideoElement>(null)
  const videoSmRef = useRef<HTMLVideoElement>(null)
  const {heroLgMovUrl} = useRoutePayload<{heroLgMovUrl: string}>()
  const {heroSmMovUrl} = useRoutePayload<{heroSmMovUrl: string}>()
  const {eyebrowBannerData} = useRoutePayload<{
    eyebrowBannerData: {
      render: boolean
      title: string
      subtitle: string | null
      url: string
      icon: string | null
      analytics: {
        'analytics-event': string
      }
    }
  }>()

  useEffect(() => {
    const playVideo = (videoElement: HTMLVideoElement | null) => {
      videoElement?.play()
    }

    const videoLgElement = videoLgRef.current
    const videoSmElement = videoSmRef.current

    const handleVideoLgElement = () => playVideo(videoLgElement)
    const handleVideoSmElement = () => playVideo(videoSmElement)

    videoLgElement?.addEventListener('canplay', handleVideoLgElement)
    videoSmElement?.addEventListener('canplay', handleVideoSmElement)

    return () => {
      videoLgElement?.removeEventListener('canplay', handleVideoLgElement)
      videoSmElement?.removeEventListener('canplay', handleVideoSmElement)
    }
  }, [])

  return (
    <Box className="enterprise-hero-background overflow-hidden">
      <EnterpriseSubNav />

      <Box paddingBlockEnd={64} className="enterprise-hero-grid">
        <Hero align="center" className="enterprise-hero">
          {eyebrowBannerData && eyebrowBannerData.render && (
            <EyebrowBanner
              href={eyebrowBannerData.url}
              className="mx-3 mx-sm-auto mb-5 mb-md-7 eyebrow-galaxy25"
              data-analytics-event={eyebrowBannerData.analytics['analytics-event']}
            >
              {eyebrowBannerData.icon && (
                <EyebrowBanner.Visual>
                  <img width="44" height="44" alt="" aria-hidden="true" src={eyebrowBannerData.icon} />
                </EyebrowBanner.Visual>
              )}

              <EyebrowBanner.Heading>{eyebrowBannerData.title}</EyebrowBanner.Heading>

              {eyebrowBannerData.subtitle && (
                <EyebrowBanner.SubHeading>{eyebrowBannerData.subtitle}</EyebrowBanner.SubHeading>
              )}
            </EyebrowBanner>
          )}

          <Hero.Heading size="1" weight="bold" className="enterprise-hero-heading">
            The AI-powered
            <br aria-hidden="true" />
            developer platform
          </Hero.Heading>

          <Hero.Description size="500" weight="normal" className="enterprise-hero-subtitle">
            To build, scale, and deliver secure software.
          </Hero.Description>

          <Hero.PrimaryAction href="/account/enterprises/new">Start free for 30 days</Hero.PrimaryAction>

          <Hero.SecondaryAction
            href="/enterprise/contact?ref_cta=Contact+Sales&ref_loc=hero&ref_page=%2Fenterprise&scid=&utm_campaign=Enterprise&utm_content=Enterprise&utm_medium=referral&utm_source=github"
            hasArrow={false}
          >
            Contact sales
          </Hero.SecondaryAction>

          <Hero.Image
            src="/images/modules/site/enterprise/2023/hero-visual.png"
            alt="A platform with GitHub logo on it"
            className="enterprise-hero-visual hide-no-pref-motion"
          />
        </Hero>

        <video
          ref={videoLgRef}
          autoPlay
          playsInline
          muted
          className="enterprise-hero-video-lg d-none d-md-block hide-reduced-motion top-n6"
          width="1400"
          height="1312"
        >
          <source src={heroLgMovUrl} type="video/mp4" />
        </video>

        <video
          ref={videoSmRef}
          autoPlay
          playsInline
          muted
          className="enterprise-hero-video-sm d-md-none hide-reduced-motion height-auto"
          width="670"
          height="1300"
        >
          <source src={heroSmMovUrl} type="video/mp4" />
        </video>
      </Box>

      <Box paddingBlockStart={12} className="enterprise-LogoSuite-wrapper">
        <LogoSuite className="enterprise-logo-suite container-lg" hasDivider={false}>
          <LogoSuite.Heading visuallyHidden>Featured sponsors</LogoSuite.Heading>

          <LogoSuite.Logobar marquee marqueeSpeed="slow">
            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-stripe.svg"
              alt="Stripe's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-twilio.svg"
              alt="Twilio's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-spotify.svg"
              alt="Spotify's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-arduino.svg"
              alt="Arduino's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-ford.svg"
              alt="Ford's logo"
              style={{height: '60px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-3m.svg"
              alt="3M's logo"
              style={{height: '40px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-pg.svg"
              alt="PG's logo"
              style={{height: '40px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-aa.svg"
              alt="American Airlines's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-nationwide.svg"
              alt="Nationwide's logo"
              style={{height: '50px'}}
            />

            <Image
              src="/images/modules/site/enterprise/2023/logos/logo-kpmg.svg"
              alt="KPMG's logo"
              style={{height: '40px'}}
            />
          </LogoSuite.Logobar>
        </LogoSuite>
      </Box>
    </Box>
  )
}
