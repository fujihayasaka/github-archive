import {Hero, RiverBreakout, Image, Text, Timeline, Link} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {Spacer} from '../components/Spacer'

export default function HeroSection() {
  return (
    <section id="hero">
      <div className="fp-Section-container fp-HeroAnim">
        <Hero data-hpc align="center" className="fp-Hero lp-Hero">
          <Hero.Label color="purple">Code Review</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            Write better code
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            On GitHub, lightweight code review tools are built into every pull request. Your team can create review
            processes that improve the quality of your code and fit neatly into your workflow.
          </Hero.Description>

          <Hero.PrimaryAction
            href="/pricing"
            {...getAnalyticsEvent({action: 'get_started', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Get started
          </Hero.PrimaryAction>

          <Hero.SecondaryAction
            href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=hero&ref_page=%2Ffeatures%2Fcode-review&utm_content=Platform&utm_medium=site&utm_source=github"
            {...getAnalyticsEvent({action: 'contact_sales', tag: 'button', context: 'CTAs', location: 'hero'})}
          >
            Contact sales
          </Hero.SecondaryAction>
        </Hero>

        <Spacer size="40px" size1012="80px" />

        <RiverBreakout className="fp-RiverBreakout">
          <RiverBreakout.Visual>
            <Image
              className="fp-RiverBreakoutVisualImage fp-HeroAnim-image"
              src="/images/modules/site/code-review/fp24/hero.webp"
              alt="Screenshot of the 'Open a pull request' interface on GitHub, showing a comparison between the 'master' and 'blue-a11y' branches. The pull request title is 'Color refresh,' with an area for adding comments and a button to 'Create pull request. The background has a pink-to-purple gradient."
              style={{aspectRatio: '416 / 227'}}
            />
          </RiverBreakout.Visual>

          <RiverBreakout.Content
            className="fp-RiverBreakout-content"
            trailingComponent={() => (
              <Timeline>
                <Timeline.Item>
                  <em>Start a new feature or propose a change to existing code with a pull request</em>—a base for your
                  team to coordinate details and refine your changes.
                </Timeline.Item>

                <Timeline.Item>
                  <em>Pull requests are fundamental to how teams review and improve code on GitHub</em>. Evolve
                  projects, propose new features, and discuss implementation details before changing your source code.
                </Timeline.Item>
              </Timeline>
            )}
          >
            <Text>
              <em>Every change starts with a pull request.</em>
            </Text>

            <Link
              size="large"
              href="https://docs.github.com/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests"
            >
              Learn pull request fundamentals
            </Link>
          </RiverBreakout.Content>
        </RiverBreakout>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
