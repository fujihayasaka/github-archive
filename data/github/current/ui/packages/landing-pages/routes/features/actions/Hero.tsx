import {Hero} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

export default function HeroSection() {
  return (
    <section id="hero">
      <div className="fp-Section-container">
        <Hero data-hpc align="center" className="fp-Hero fp-HeroAnim">
          <Hero.Label color="green">GitHub Actions</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            Automate your workflow from idea to production
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            GitHub Actions makes it easy to automate all your software workflows, now with world-class CI/CD. Build,
            test, and deploy your code right from GitHub. Make code reviews, branch management, and issue triaging work
            the way you want.
          </Hero.Description>

          <Hero.PrimaryAction
            href="https://docs.github.com/actions"
            {...getAnalyticsEvent({action: 'get_started', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Get started
          </Hero.PrimaryAction>

          <Hero.SecondaryAction
            href="/enterprise/contact?ref_cta=Contact+Sales&ref_loc=hero&ref_page=%2Ffeatures%2Factions&scid=&utm_campaign=Actions_feature_page_contact_sales_cta_utmroutercampaign&utm_content=Actions&utm_medium=site&utm_source=github"
            {...getAnalyticsEvent({action: 'contact_sales', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Contact sales
          </Hero.SecondaryAction>

          <Hero.Image
            className="fp-Hero-image fp-HeroAnim-image"
            src="/images/modules/site/actions/fp24/hero.webp"
            alt="Screenshot of a GitHub Actions workflow titled 'matrix-build-deploy.yml' displaying a pipeline with three stages: Build, Test, and Publish. The Build stage has completed successfully in 1 minute and 42 seconds. The Test stage includes builds for Linux, macOS, and Windows, all of which have also completed successfully with their respective durations. The final stage, Publish, shows that the publishing steps for Linux, macOS, and Windows are pending and waiting for approval. The background features a gradient transitioning from green to blue."
            style={{aspectRatio: '1248 / 661'}}
          />
        </Hero>
      </div>
    </section>
  )
}
