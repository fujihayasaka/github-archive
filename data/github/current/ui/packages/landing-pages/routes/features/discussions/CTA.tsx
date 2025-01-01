import {ThemeProvider, CTABanner, Button} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {Spacer} from '../components/Spacer'

export default function CTASection() {
  return (
    <section id="cta">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <ThemeProvider colorMode="dark" style={{backgroundColor: 'transparent'}}>
          <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
            <CTABanner.Heading size="2">Start the conversation with your community</CTABanner.Heading>

            <CTABanner.ButtonGroup buttonsAs="a">
              <Button
                href="https://docs.github.com/discussions/quickstart"
                {...getAnalyticsEvent({
                  action: 'try_now',
                  tag: 'button',
                  context: 'CTAs',
                  location: 'bottom_cta_section',
                })}
              >
                Try now
              </Button>

              <Button
                href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fdiscussions&utm_content=Platform&utm_medium=site&utm_source=github"
                {...getAnalyticsEvent({
                  action: 'contact_sales',
                  tag: 'button',
                  context: 'CTAs',
                  location: 'bottom_cta_section',
                })}
              >
                Contact sales
              </Button>
            </CTABanner.ButtonGroup>
          </CTABanner>
        </ThemeProvider>
      </div>
    </section>
  )
}
