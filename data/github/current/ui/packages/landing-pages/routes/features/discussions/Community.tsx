import {SectionIntro, Text, Image, Grid, Heading} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function CommunitySection() {
  return (
    <section id="community">
      <div className="fp-Section-container">
        <Spacer size="32px" size1012="48px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">Get inspired</SectionIntro.Heading>

          <SectionIntro.Description>See how your favorite communities are using discussions</SectionIntro.Description>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Grid className="lp-Grid">
          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/vercel/next.js/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/next-js.svg"
                  alt="Next.js logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  Next.js
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  10k+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/tailwindlabs/tailwindcss/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/tailwindcss.svg"
                  alt="TailwindCSS logo"
                  loading="lazy"
                />
              </div>
              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  TailwindCSS
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  3k+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/Homebrew/discussions/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/homebrew.svg"
                  alt="Homebrew logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  Homebrew
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  4k+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/twbs/bootstrap/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/bootstrap.svg"
                  alt="Bootstrap logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  Bootstrap
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  600+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/laravel/framework/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/laravel.svg"
                  alt="Laravel logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  Laravel
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  1.6k+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a className="lp-CommunityItem" href="https://github.com/d3/d3/discussions" rel="nofollow noreferrer">
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/d3-js.svg"
                  alt="D3.js logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  D3.js
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  30k+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a
              className="lp-CommunityItem"
              href="https://github.com/symfony/symfony/discussions"
              rel="nofollow noreferrer"
            >
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/symfony.svg"
                  alt="Symfony logo"
                  loading="lazy"
                />
              </div>

              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  Symfony
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  700+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, small: 6, medium: 4, large: 4, xlarge: 3}}>
            <a className="lp-CommunityItem" href="https://github.com/vuejs/core/discussions" rel="nofollow noreferrer">
              <div className="lp-CommunityItem-visual">
                <Image
                  className="lp-CommunityItem-logo"
                  src="/images/modules/site/discussions/fp24/community/vuejs.svg"
                  alt="VueJS logo"
                  loading="lazy"
                />
              </div>
              <div className="lp-CommunityItem-content">
                <Heading as="h3" size="6" className="lp-CommunityItem-heading">
                  VueJS
                </Heading>

                <Text as="p" className="lp-CommunityItem-description" size="100" variant="muted">
                  50+ discussions
                </Text>
              </div>
            </a>
          </Grid.Column>
        </Grid>
      </div>
    </section>
  )
}
