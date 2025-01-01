import {CTABanner, Button} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function CTASection() {
  return (
    <section id="cta">
      <div className="fp-Section-container">
        <Spacer size="48px" size1012="96px" />

        <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
          <CTABanner.Heading size="2">The future of workflow automation is now</CTABanner.Heading>

          <CTABanner.Description className="lp-CTABannerDescription">
            Get started with GitHub Actions today and explore community created <br className="fp-breakWhenWide" />
            actions in the GitHub Marketplace.
          </CTABanner.Description>

          <CTABanner.ButtonGroup buttonsAs="a">
            <Button href="https://docs.github.com/actions">Get started</Button>

            <Button href="/enterprise/contact?ref_cta=Contact+Sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Factions&scid=&utm_campaign=Actions_feature_page_contact_sales_cta_utmroutercampaign&utm_content=Actions&utm_medium=site&utm_source=github">
              Contact sales
            </Button>
          </CTABanner.ButtonGroup>
        </CTABanner>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
