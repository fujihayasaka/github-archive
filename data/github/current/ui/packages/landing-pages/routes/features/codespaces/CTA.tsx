import {CTABanner, Button} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function CTASection() {
  return (
    <section id="cta">
      <div className="fp-Section-container">
        <Spacer size="40px" size1012="80px" />

        <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
          <CTABanner.Heading size="2">Start coding in seconds with Codespaces</CTABanner.Heading>

          <CTABanner.Description className="lp-CTABannerDescription">
            Go to any repository and open your own Codespaces environment instantly.
          </CTABanner.Description>

          <CTABanner.ButtonGroup buttonsAs="a">
            <Button href="/codespaces">Get started</Button>

            <Button href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fcodespaces&utm_content=Platform&utm_medium=site&utm_source=github">
              Contact Sales
            </Button>
          </CTABanner.ButtonGroup>
        </CTABanner>
      </div>
    </section>
  )
}
