import {useEffect} from 'react'
import {ThemeProvider, SectionIntro, Image, FAQ, CTABanner, Button, Testimonial} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {Spacer} from '../components/Spacer'

export default function CTASection() {
  // Animate testimonial visuals

  useEffect(() => {
    const intro = document.querySelector('.lp-TestimonialsContainer')

    if (intro) {
      const observer = new IntersectionObserver(
        entries => {
          const entry = entries[0]
          if (entry?.isIntersecting) {
            intro.classList.add('isVisible')
          } else {
            intro.classList.remove('isVisible')
          }
        },
        {
          root: null, // Use the viewport as the root
          rootMargin: '0px',
          threshold: 0.5, // Trigger when 50% is visible
        },
      )

      observer.observe(intro)

      return () => {
        observer.unobserve(intro)
      }
    }
  }, [])

  return (
    <section id="cta" className="fp-Section--isRaised lp-SectionCTA">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">What developers are saying</SectionIntro.Heading>
        </SectionIntro>
      </div>

      <Spacer size="48px" size1012="96px" />

      <div className="fp-Section-container lp-TestimonialsContainer">
        <Image
          className="lp-TestimonialsVisual lp-TestimonialsVisual--1"
          src="/images/modules/site/issues/fp24/testimonial-bg-1.webp"
          width={574}
          alt=""
          loading="lazy"
        />

        <Image
          className="lp-TestimonialsVisual lp-TestimonialsVisual--2"
          src="/images/modules/site/issues/fp24/testimonial-bg-2.webp"
          width={612}
          alt=""
          loading="lazy"
        />

        <Testimonial quoteMarkColor="purple" size="large" className="lp-Testimonial">
          <Testimonial.Quote className="lp-TestimonialQuote">
            The new planning and tracking functionality keeps my project management close to my code. I no longer find
            myself needing to reach for spreadsheets or 3P tools which go stale instantly.
          </Testimonial.Quote>

          <Testimonial.Name position="Development Manager">Dan Godfrey</Testimonial.Name>

          <Testimonial.Logo style={{marginRight: '16px'}}>
            <img
              alt="Shopify Logo"
              src="/images/modules/site/issues/fp24/testimonial-logo-shopify.svg"
              width={124}
              loading="lazy"
            />
          </Testimonial.Logo>
        </Testimonial>
      </div>

      <Spacer size="48px" size1012="96px" />

      <div className="fp-Section-container">
        <ThemeProvider colorMode="dark" style={{backgroundColor: 'transparent'}}>
          <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
            <CTABanner.Heading size="2">Flexible project planning for developers</CTABanner.Heading>

            <CTABanner.ButtonGroup buttonsAs="a">
              <Button
                href="https://docs.github.com/issues"
                {...getAnalyticsEvent({
                  action: 'get_started',
                  tag: 'button',
                  context: 'CTAs',
                  location: 'bottom_cta_section',
                })}
              >
                Get started
              </Button>

              <Button
                href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fissues&utm_content=Platform&utm_medium=site&utm_source=github"
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

        <Spacer size="64px" size1012="128px" />

        <FAQ className="fp-FAQ">
          <FAQ.Heading>Frequently asked questions</FAQ.Heading>

          <FAQ.Item>
            <FAQ.Question>What is GitHub Issues?</FAQ.Question>

            <FAQ.Answer>
              <p>
                We all need a way to plan our work, track issues, and discuss the things we build. Our answer to this
                universal question is GitHub Issues, and it’s built-in to every repository. GitHub’s issue tracking is
                unique because of our focus on simplicity, references, and elegant formatting.
              </p>

              <p>
                With GitHub Issues, you can express ideas with GitHub Flavored Markdown, assign and mention
                contributors, react with emojis, clarify with attachments and videos, plus reference code like commits,
                pull requests, and deploys. With task lists, you can break big issues into tasks, further organize your
                work with milestones and labels, and track relationships and dependencies.
              </p>

              <p>We built GitHub Issues for developers. It is simple, adaptable, and powerful.</p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>What are Projects?</FAQ.Question>

            <FAQ.Answer>
              <p>
                As teams and projects grow, how we work evolves. Tools that hard-code a methodology are too specific and
                rigid to adapt to any moment. Often, we find ourselves creating a spreadsheet or pulling out a notepad
                to have the space to think. Then our planning is disconnected from where the work happens.
              </p>

              <p>
                The new Projects connect your planning directly to the work your teams are doing and flexibly adapt to
                whatever your team needs at any point. Built like a spreadsheet, project tables give you a live canvas
                to filter, sort, and group issues and pull requests. You can use it, or the accompanying project board,
                along with custom fields, to track a sprint, plan a feature, or manage a large-scale release.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Can I update existing Projects to use the new capabilities?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Yes. You can migrate your existing Projects (classic) to the new GitHub Projects through a new feature
                preview.
              </p>

              <p>How it works:</p>

              <ul>
                <li>
                  We’ll create a new project and copy all of the data from your existing project (classic) board to the
                  new one.
                </li>

                <li>Once the data is copied, you can use the new project with all the new capabilities.</li>

                <li>
                  Once the new project is ready, we will prompt you to close your “old” project, as the old project is
                  not kept in sync.
                </li>
              </ul>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>What plans have access to Projects?</FAQ.Question>

            <FAQ.Answer>
              <p>
                All users have access to the free tier of GitHub Issues and Projects. For more information about paid
                tiers, see our pricing page.
              </p>

              <p>
                Historical charts are available for all Enterprise organizations and are currently in Preview for
                organizations on Team plans.**
              </p>

              <p>**Subject to change as we add future capabilities.</p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Will the new Projects experience be available in GitHub Enterprise Server?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Yes! GitHub Enterprise Server (GHES) support follows our regular cadence of one to two quarters before
                enabling the on-premises functionality.
              </p>
            </FAQ.Answer>
          </FAQ.Item>
        </FAQ>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
