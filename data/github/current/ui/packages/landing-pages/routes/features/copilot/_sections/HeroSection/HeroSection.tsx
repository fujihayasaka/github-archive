import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useMemo} from 'react'
import {Box, BreakpointSize, Grid, Hero, InlineLink, useWindowSize, Text} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {ContentfulLogoSuite} from '@github-ui/swp-core/components/contentful/ContentfulLogoSuite'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'
import type {PrimerComponentLogoSuite} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentLogoSuite'
import type {PrimerComponentSubnav} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSubnav'

import type {GenericSectionWithIds, GenericContent} from '../../../../../brand/lib/types/contentful'

import {cohortFunnelBuilder} from '../../../../../lib/analytics'

import heroBg from '../../_assets/hero-bg.jpg'
import heroBgLg from '../../_assets/hero-bg-lg.webp'
import heroBgSm from '../../_assets/hero-bg-sm.jpg'

import {default as IdeCta, type IdeLinks} from '../../_components/IdeCta/IdeCta'
import VSCodeCta from '../../_components/VSCodeCta'

import {HeroVideo} from './HeroVideo'

type Props = {
  contentfulContent: GenericSectionWithIds
  subnav?: PrimerComponentSubnav
  copilotIdeDeepLinks?: IdeLinks
}

export function HeroSection(props: Props) {
  const {subnav, contentfulContent, copilotIdeDeepLinks} = props

  const {featuresCopilotHero} = contentfulContent.ids as {
    featuresCopilotHero: GenericContent
  }

  const {label, heading, links, media} = featuresCopilotHero.fields
  const primaryCta = links?.at(0)
  const secondaryCta = links?.at(1)

  const heroVideoLarge = media?.find(item => item.fields.id === 'heroVideoLarge')
  const heroVideoSmall = media?.find(item => item.fields.id === 'heroVideoSmall')
  const heroPosterLarge = media?.find(item => item.fields.id === 'heroPosterLarge')
  const heroPosterSmall = media?.find(item => item.fields.id === 'heroPosterSmall')

  const logosComponent = contentfulContent.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentLogoSuite',
  ) as PrimerComponentLogoSuite | undefined

  const {cft} = useRoutePayload<{cft: string}>()
  const withCft = cohortFunnelBuilder(cft)

  const isNewMarketingCTAEnabled = isFeatureEnabled('copilot_f2p_marketing_cta')
  const isPostMsBuildLaunch = isFeatureEnabled('site_msbuild_launch')

  const windowSize = useWindowSize()
  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize.currentBreakpointSize],
  )
  const showIdeCta = useMemo(() => isDesktopView && isNewMarketingCTAEnabled, [isDesktopView, isNewMarketingCTAEnabled])

  return (
    <div className="position-relative">
      <Box className="lp-SubNav-spacer" />

      {subnav ? <ContentfulSubnav component={subnav} className="lp-Hero-subnav lp-Hero-subnav--highContrast" /> : null}

      {!isPostMsBuildLaunch && (
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
      )}

      <section id="hero" className="lp-Section lp-Section--compact lp-Section--hero">
        <Grid>
          <Grid.Column span={12}>
            <Hero data-hpc align="center" className="lp-Hero">
              {label ? (
                <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label lp-ConicGradientBorder-hero d-inline-block mb-4">
                  <Hero.Label
                    size="large"
                    color="purple-red"
                    className="lp-ConicGradientBorder-label-inner"
                    style={{minHeight: '30px', height: 'auto', marginBottom: '0'}}
                  >
                    {label.fields.text}
                  </Hero.Label>
                </div>
              ) : null}

              {heading ? (
                <Hero.Heading size="1" weight="bold" className="lp-Hero-heading lp-Hero-heading-mask">
                  {heading}
                </Hero.Heading>
              ) : null}

              <div className="lp-Hero-ctaButtons">
                {primaryCta &&
                  (showIdeCta ? (
                    <IdeCta deepLinks={copilotIdeDeepLinks} />
                  ) : (
                    <Hero.PrimaryAction
                      href={primaryCta.fields.href}
                      hasArrow={false}
                      {...getAnalyticsEvent({
                        action: primaryCta.fields.text,
                        tag: 'button',
                        context: 'CTAs',
                        location: 'hero',
                      })}
                    >
                      {primaryCta.fields.text}
                    </Hero.PrimaryAction>
                  ))}

                {secondaryCta ? (
                  <Hero.SecondaryAction
                    href={withCft(secondaryCta.fields.href)}
                    hasArrow={false}
                    variant="subtle"
                    {...getAnalyticsEvent({
                      action: secondaryCta.fields.text,
                      tag: 'button',
                      context: 'CTAs',
                      location: 'hero',
                    })}
                  >
                    {secondaryCta.fields.text}
                  </Hero.SecondaryAction>
                ) : null}
              </div>

              {isDesktopView && isNewMarketingCTAEnabled && (
                <Text weight="medium" style={{marginTop: '1rem'}}>
                  Or try{' '}
                  <InlineLink href="https://github.com/copilot" className="tertiary-cta">
                    Copilot on GitHub
                  </InlineLink>{' '}
                </Text>
              )}

              {(!isDesktopView || !isNewMarketingCTAEnabled) && <VSCodeCta />}
            </Hero>

            {heroVideoLarge ? (
              <HeroVideo
                description={heroVideoLarge.fields.description}
                posterSrcLarge={heroPosterLarge?.fields.asset.fields.file.url}
                posterSrcSmall={heroPosterSmall?.fields.asset.fields.file.url}
                videoSrcLarge={heroVideoLarge.fields.asset.fields.file.url}
                videoSrcSmall={heroVideoSmall?.fields.asset.fields.file.url}
              />
            ) : null}

            {logosComponent ? <ContentfulLogoSuite component={logosComponent} className="lp-LogoSuite" /> : null}

            {!isPostMsBuildLaunch && (
              <Box className="lp-Hero-fade">
                <svg
                  width="1600"
                  height="502"
                  aria-hidden="true"
                  style={{width: '100%', height: 'auto', display: 'block'}}
                />
              </Box>
            )}
          </Grid.Column>
        </Grid>

        <div className="lp-Hero-cover" />
      </section>
    </div>
  )
}
