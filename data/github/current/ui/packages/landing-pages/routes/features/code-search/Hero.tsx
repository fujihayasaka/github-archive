import {Hero} from '@primer/react-brand'

export default function HeroSection() {
  return (
    <section id="hero">
      <div className="fp-Section-container">
        <Hero data-hpc align="center" className="fp-Hero fp-HeroAnim">
          <Hero.Label color="green">Code Search</Hero.Label>

          <Hero.Heading className="fp-Hero-heading" size="2">
            Exactly what you’re <br className="fp-breakWhenWide" /> looking for
          </Hero.Heading>

          <Hero.Description className="fp-Hero-description" size="300">
            With GitHub code search, your code—and the world’s—is at your fingertips.
          </Hero.Description>

          <Hero.PrimaryAction href="/search?type=code&auto_enroll=true">Try now</Hero.PrimaryAction>

          <Hero.SecondaryAction href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=hero&ref_page=%2Ffeatures%2Fcode-search&utm_content=Platform&utm_medium=site&utm_source=github">
            Contact sales
          </Hero.SecondaryAction>

          <Hero.Image
            className="fp-Hero-image fp-HeroAnim-image"
            src="/images/modules/site/code-search/fp24/hero.webp"
            alt="Screenshot of the GitHub code review interface displaying a repository's file structure and code editor. The left panel shows a file explorer with folders such as .github, .reuse, LICENSES, and library, with the wtf8.rs file currently open in the main editor. The code in the editor is written in Rust, defining a CodePoint struct and its related implementation. A search box at the bottom left shows search results for 'CodePoint' within the repository, listing various matches such as class CodePoint and implementation CodePoint. On the right side, a detailed symbol reference panel shows the definition of CodePoint and lists 24 references found in the code. The background features a gradient from green to teal, highlighting the focused and interactive nature of the code review process."
            style={{aspectRatio: '416 / 227'}}
          />
        </Hero>
      </div>
    </section>
  )
}
