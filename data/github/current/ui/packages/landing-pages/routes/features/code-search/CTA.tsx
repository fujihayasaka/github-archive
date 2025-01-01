import {
  ThemeProvider,
  SectionIntro,
  Grid,
  Testimonial,
  CTABanner,
  Button,
  FAQ,
  TextRevealAnimation,
} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {Spacer} from '../components/Spacer'

export default function CTASection() {
  return (
    <section className="fp-Section--isRaised">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">What developers are saying</SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="48px" size1012="96px" />

        <Grid className="lp-Grid lp-Grid--isRaised">
          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
            <Testimonial quoteMarkColor="green">
              <Testimonial.Quote>
                <TextRevealAnimation className="lp-Testimonials-text">
                  Code search makes it effortless to quickly find what Iʼm looking for in my code, or across all of
                  GitHub
                </TextRevealAnimation>
              </Testimonial.Quote>

              <Testimonial.Name position="Software Engineer">Keith Smiley</Testimonial.Name>

              <Testimonial.Avatar
                src="/images/modules/site/code-search/fp24/testimonials-avatar-keith.jpg"
                alt="Circular avatar from Keith Smiley's GitHub profile"
              />
            </Testimonial>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
            <Testimonial quoteMarkColor="green">
              <Testimonial.Quote>
                <TextRevealAnimation className="lp-Testimonials-text">
                  Code search turns what wouldʼve been a ~10 minute grep search into a 2 second UI search
                </TextRevealAnimation>
              </Testimonial.Quote>

              <Testimonial.Name position="Platform Engineer">Marco Montagna</Testimonial.Name>

              <Testimonial.Avatar
                src="/images/modules/site/code-search/fp24/testimonials-avatar-marco.jpg"
                alt="Circular avatar from Marco Montagna's GitHub profile"
              />
            </Testimonial>
          </Grid.Column>
        </Grid>

        <Spacer size="48px" size1012="96px" />

        <ThemeProvider colorMode="dark" style={{backgroundColor: 'transparent'}}>
          <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
            <CTABanner.Heading size="2">Find more, search less</CTABanner.Heading>

            <CTABanner.ButtonGroup buttonsAs="a">
              <Button
                href="/search?type=code"
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
                className="lp-CTABanner-secondary"
                href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fcode-search&utm_content=Platform&utm_medium=site&utm_source=github"
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

        <Spacer size="48px" size1012="96px" />

        <FAQ id="faq" className="lp-FAQ">
          <FAQ.Heading>Frequently asked questions</FAQ.Heading>

          <FAQ.Item>
            <FAQ.Question>Do I need to set up my repositories to support code navigation?</FAQ.Question>

            <FAQ.Answer>
              <p>No, code navigation works out of the box, with zero configuration required.</p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Who can search my code?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Public code is searchable by anyone, but private code can only be searched by users who have access to
                it.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>How much does the new code search and code view cost?</FAQ.Question>

            <FAQ.Answer>
              <p>The new code search and code view are free for users of GitHub.com.</p>
            </FAQ.Answer>
          </FAQ.Item>
        </FAQ>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
