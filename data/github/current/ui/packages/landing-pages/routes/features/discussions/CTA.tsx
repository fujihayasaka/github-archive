import {ThemeProvider, CTABanner, Button} from '@primer/react-brand'

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
              <Button href="https://docs.github.com/discussions/quickstart">Try now</Button>

              <Button href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fdiscussions&utm_content=Platform&utm_medium=site&utm_source=github">
                Contact sales
              </Button>
            </CTABanner.ButtonGroup>
          </CTABanner>
        </ThemeProvider>
      </div>
    </section>
  )
}
