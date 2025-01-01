import {Hero} from '@primer/react-brand'

export default function HeroSection() {
  return (
    <section id="hero" className="lp-Hero-wrapper fp-HeroAnim">
      <div className="fp-Section-container">
        <Hero data-hpc className="fp-Hero lp-Hero" align="center">
          <Hero.Label color="purple">GitHub Discussions</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            The home for
            <br />
            developer communities
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            Ask questions, share ideas, and build connections with each other—all right next to your code. GitHub
            Discussions enables healthy and productive software collaboration.
          </Hero.Description>

          <Hero.PrimaryAction href="https://docs.github.com/discussions/quickstart">Try now</Hero.PrimaryAction>

          <Hero.SecondaryAction href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=hero&ref_page=%2Ffeatures%2Fdiscussions&utm_content=Platform&utm_medium=site&utm_source=github">
            Contact sales
          </Hero.SecondaryAction>
        </Hero>
      </div>

      <div className="fp-HeroAnim-image lp-Hero-bg--discussions">
        <span className="sr-only">
          Screenshot of a GitHub Discussions page for the ’octoinvaders’ project, showing categorized discussion threads
          with tags like ’answered’ and ’Long term.’ The interface features playful elements like a mona emjoi and a
          rocket icon, highlighting community interaction.
        </span>
      </div>
    </section>
  )
}
