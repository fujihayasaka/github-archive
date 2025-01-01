import {SectionIntro, Grid, Testimonial, TextRevealAnimation} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function TestimonialsSection() {
  return (
    <section id="testimonials">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">What developers are saying</SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Grid className="lp-Grid">
          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
            <Testimonial quoteMarkColor="green">
              <Testimonial.Quote>
                <TextRevealAnimation className="lp-Testimonials-text">
                  What used to be a 15-step process is just one step: open Codespaces and you’re off and running.
                </TextRevealAnimation>
              </Testimonial.Quote>

              <Testimonial.Name position="Developer Lead, Synergy">Clint Chester</Testimonial.Name>

              <Testimonial.Avatar
                src="/images/modules/site/codespaces/fp24/testimonials-avatar-clint.png"
                alt="Circular avatar from Clint Chester's GitHub profile"
              />
            </Testimonial>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
            <Testimonial quoteMarkColor="green">
              <Testimonial.Quote>
                <TextRevealAnimation className="lp-Testimonials-text">
                  Codespaces… lets developers skip the tedious, error-prone stuff that normally stands between them and
                  getting started on real work.
                </TextRevealAnimation>
              </Testimonial.Quote>

              <Testimonial.Name position="Cloud Capability Lead, KPMG, UK">Keith Annette</Testimonial.Name>

              <Testimonial.Avatar
                src="/images/modules/site/codespaces/fp24/testimonials-avatar-keith.png"
                alt="Circular avatar from Keith Annette's GitHub profile"
              />
            </Testimonial>
          </Grid.Column>
        </Grid>
      </div>
    </section>
  )
}
