import {SectionIntro, Stack, Card} from '@primer/react-brand'

import {GraphIcon, RepoIcon} from '@primer/octicons-react'

import {Spacer} from '../components/Spacer'

export default function HeroSection() {
  return (
    <section id="pricing">
      <div className="fp-Section-container">
        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">Simple, pay-as-you-go pricing</SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Stack
          className="lp-CardTheme"
          direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
          gap="spacious"
          padding="none"
        >
          <div className="lp-CardWrapper">
            <Card
              className="lp-Card fp-gradientBorder"
              ctaText="Learn about storage and minutes"
              href="https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions#included-storage-and-minutes"
              fullWidth
            >
              <Card.Icon icon={<RepoIcon />} color="green" />

              <Card.Heading size="6">GitHub Actions is free for public repositories</Card.Heading>

              <Card.Description>
                Our open source commitment means you get free CI/CD minutes on GitHub-hosted runners, tailored to every
                plan for public repositories.
              </Card.Description>
            </Card>
          </div>

          <div className="lp-CardWrapper">
            <Card
              className="lp-Card fp-gradientBorder"
              ctaText="View pricing"
              href="https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions#per-minute-rates"
              fullWidth
            >
              <Card.Icon icon={<GraphIcon />} color="green" />

              <Card.Heading size="6">Host your own runners or use GitHub-hosted runners</Card.Heading>

              <Card.Description>
                Run your Actions workflows with your own self-hosted runners or use GitHub-hosted runners. Choose from
                Linux, Windows, or macOS, and customize with more cores, ARM, or GPU options for enhanced performance.
                View pricing and the different runner types on our docs.
              </Card.Description>
            </Card>
          </div>
        </Stack>
      </div>
    </section>
  )
}
