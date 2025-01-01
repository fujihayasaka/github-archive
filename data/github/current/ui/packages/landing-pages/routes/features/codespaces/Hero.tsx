import {Hero} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

export default function HeroSection() {
  return (
    <section id="hero" className="lp-Hero-wrapper">
      <div className="lp-Hero-bg--codespaces" />

      <div className="fp-Section-container">
        <Hero data-hpc className="fp-Hero fp-HeroAnim lp-Hero" align="center">
          <Hero.Label color="green">GitHub Codespaces</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            Secure development made simple
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            GitHub Codespaces gets you up and coding faster with fully configured, secure cloud development environments
            native to GitHub.
          </Hero.Description>

          <Hero.PrimaryAction
            href="/codespaces"
            {...getAnalyticsEvent({action: 'get_started', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Get started
          </Hero.PrimaryAction>

          <Hero.SecondaryAction
            href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fcodespaces&utm_content=Platform&utm_medium=site&utm_source=github"
            {...getAnalyticsEvent({action: 'contact_sales', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Contact sales
          </Hero.SecondaryAction>

          <Hero.Image
            className="fp-Hero-image fp-HeroAnim-image lp-Hero-image"
            src="/images/modules/site/codespaces/fp24/hero.webp"
            alt="Screenshot of GitHub Codespaces, showing a split-screen interface. On the left side, there's an HTML file (index.html) being edited, with code defining a webpage structure, including an image, a navigation button, and a section for a headline and paragraph text. Below the code editor, there's a terminal window displaying tasks being started and completed, such as watch-extension: vscode-api-tests. On the right side of the screen, the rendered webpage is displayed, featuring a bold headline 'Mona Sans. A Variable Font' with a subheading describing the typeface. Below the text is an illustration of the GitHub mascot, Mona the Octocat, standing on a floating platform."
            style={{aspectRatio: '1248 / 789'}}
          />
        </Hero>
      </div>
    </section>
  )
}
