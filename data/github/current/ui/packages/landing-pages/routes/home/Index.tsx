import {useEffect, useRef} from 'react'
import resolveResponse from 'contentful-resolve-response'

import {ThemeProvider, Grid} from '@primer/react-brand'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {ContentfulInlineFootnotesList} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnotesList'
import {FootnotesProvider} from '@github-ui/swp-core/components/contentful/FootnotesContext'

import {ZodSilentErrorBoundary} from '../../components/ZodSilentErrorBoundary/ZodSilentErrorBoundary'
import {toPayload} from '../../lib/types/payload'
import {toBrandPage} from '../../brand/lib/types/contentful'
import type {GenericSectionWithIds} from '../../brand/lib/types/contentful'

import BackToTop from './components/BackToTop/BackToTop'
import WebGLAssets from './webgl-utils/assets'

import {AutomationSection} from './_sections/AutomationSection/AutomationSection'
import {CollaborationSection} from './_sections/CollaborationSection/CollaborationSection'
import {CtaSection} from './_sections/CtaSection/CtaSection'
import {CustomerStoriesSection} from './_sections/CustomerStoriesSection/CustomerStoriesSection'
import {HeroSection} from './_sections/HeroSection/HeroSection'
import {SecuritySection} from './_sections/SecuritySection/SecuritySection'

import Automation from './Automation'
import Collaboration from './Collaboration'
import Cta from './Cta'
import CustomerStories from './CustomerStories'
import FootnotesSection from './FootnotesSection'
import Intro from './Intro'
import Security from './Security'

export function Home() {
  const isContentfulEnabled = isFeatureEnabled('site_homepage_contentful')
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())

  const assetsRef = useRef<WebGLAssets | null>(new WebGLAssets())

  useEffect(() => {
    let isClosed = false
    const assets = assetsRef.current

    if (assets)
      assets.load(() => {
        if (!isClosed) {
          // All assets loaded
          assets.executeCallbacks()
        }
      })
    return () => {
      isClosed = true
    }
  }, [])

  if (isContentfulEnabled && contentfulRawJsonResponse) {
    const contentfulResponse = resolveResponse(contentfulRawJsonResponse)
    const page = toBrandPage(contentfulResponse)

    const {automationSection, collaborationSection, ctaSection, customerStoriesSection, heroSection, securitySection} =
      page.ids as {
        automationSection: GenericSectionWithIds
        collaborationSection: GenericSectionWithIds
        ctaSection: GenericSectionWithIds
        customerStoriesSection: GenericSectionWithIds
        heroSection: GenericSectionWithIds
        securitySection: GenericSectionWithIds
      }

    return (
      <ZodSilentErrorBoundary>
        <ThemeProvider colorMode="dark" className="lp-Home">
          <FootnotesProvider>
            {heroSection ? <HeroSection assetsRef={assetsRef} contentfulContent={heroSection} /> : null}

            {automationSection ? (
              <AutomationSection assetsRef={assetsRef} contentfulContent={automationSection} />
            ) : null}

            {securitySection ? <SecuritySection assetsRef={assetsRef} contentfulContent={securitySection} /> : null}

            {collaborationSection ? (
              <CollaborationSection assetsRef={assetsRef} contentfulContent={collaborationSection} />
            ) : null}

            {customerStoriesSection ? (
              <CustomerStoriesSection assetsRef={assetsRef} contentfulContent={customerStoriesSection} />
            ) : null}

            {ctaSection ? <CtaSection contentfulContent={ctaSection} /> : null}

            <Grid>
              <Grid.Column span={12}>
                <ContentfulInlineFootnotesList className="pt-0" />
              </Grid.Column>
            </Grid>

            <BackToTop />
          </FootnotesProvider>
        </ThemeProvider>
      </ZodSilentErrorBoundary>
    )
  }

  return (
    <ThemeProvider colorMode="dark" className="lp-Home">
      <Intro assetsRef={assetsRef} />
      <Automation assetsRef={assetsRef} />
      <Security assetsRef={assetsRef} />
      <Collaboration assetsRef={assetsRef} />
      <CustomerStories assetsRef={assetsRef} />
      <Cta />
      <FootnotesSection />
      <BackToTop />
    </ThemeProvider>
  )
}
