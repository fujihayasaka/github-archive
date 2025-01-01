import {Hero, LogoSuite, Image} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {Spacer} from '../components/Spacer'

export default function HeroSection() {
  return (
    <section id="hero">
      <div className="fp-Section-container">
        <Hero data-hpc align="center" className="fp-Hero fp-HeroAnim">
          <Hero.Label color="purple">GitHub Issues</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            Project planning <br className="fp-breakWhenWide" /> for developers
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            Create issues, break them into tasks, track relationships, add custom fields, and have conversations.
            Visualize large projects as tables, boards, or roadmaps, and automate everything with code.
          </Hero.Description>

          <Hero.PrimaryAction
            href="https://docs.github.com/issues"
            {...getAnalyticsEvent({action: 'get_started', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Get started
          </Hero.PrimaryAction>

          <Hero.SecondaryAction
            href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=hero&ref_page=%2Ffeatures%2Fissues&utm_content=Platform&utm_medium=site&utm_source=github"
            {...getAnalyticsEvent({action: 'contact_sales', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Contact sales
          </Hero.SecondaryAction>

          <Hero.Image
            className="fp-Hero-image fp-HeroAnim-image"
            src="/images/modules/site/issues/fp24/hero.webp"
            alt="Illustration of project table view with cards grouped sorted by devleopment 'Area' custom field."
            style={{aspectRatio: '208 / 103'}}
          />
        </Hero>

        <Spacer size="48px" size1012="96px" />

        <LogoSuite className="fp-LogoSuite" hasDivider={false}>
          <LogoSuite.Heading visuallyHidden>Featured logos</LogoSuite.Heading>

          <LogoSuite.Logobar variant="muted">
            <Image
              src="/images/modules/site/issues/fp24/logo-shopify.svg"
              alt="Shopify"
              style={{height: '42px', filter: 'none', alignSelf: 'center'}}
            />

            <Image
              src="/images/modules/site/issues/fp24/logo-vercel.svg"
              alt="Vercel"
              style={{height: '30px', filter: 'none', alignSelf: 'center'}}
            />

            <Image
              src="/images/modules/site/issues/fp24/logo-stripe.svg"
              alt="Stripe"
              style={{height: '48px', filter: 'none', alignSelf: 'center'}}
            />

            <Image
              src="/images/modules/site/issues/fp24/logo-ford.svg"
              alt="Ford"
              style={{height: '48px', filter: 'none', alignSelf: 'center'}}
            />

            <Image
              src="/images/modules/site/issues/fp24/logo-nasa.svg"
              alt="NASA"
              style={{height: '34px', filter: 'none', alignSelf: 'center'}}
            />
          </LogoSuite.Logobar>
        </LogoSuite>
      </div>
    </section>
  )
}
