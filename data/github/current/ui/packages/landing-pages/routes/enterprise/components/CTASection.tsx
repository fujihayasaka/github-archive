import {Box, Button, Card, CTABanner, Grid, Stack, ThemeProvider} from '@primer/react-brand'
import {BookIcon, MarkGithubIcon} from '@primer/octicons-react'

import FAQSection from './FAQSection'
import FootnotesSection from './FootnotesSection'

export default function CTASection() {
  return (
    <ThemeProvider
      colorMode="dark"
      style={{backgroundColor: 'var(--base-color-scale-black-0)'}}
      className="enterprise-section-rounded"
    >
      <Grid>
        <Grid.Column>
          <Box
            paddingBlockStart={{
              narrow: 64,
              regular: 128,
            }}
            paddingBlockEnd={{
              narrow: 64,
              regular: 128,
            }}
          >
            <Box
              className="cta-banner-box"
              paddingBlockStart={{
                narrow: 64,
                regular: 32,
                wide: 'none',
              }}
              paddingBlockEnd={{
                narrow: 64,
                regular: 32,
                wide: 'none',
              }}
            >
              <CTABanner hasShadow={false} hasBackground={false} align="center">
                <CTABanner.Heading weight="bold" className="mb-4">
                  Start your journey with GitHub
                </CTABanner.Heading>

                <CTABanner.ButtonGroup>
                  <Button
                    as="a"
                    href="/organizations/enterprise_plan?ref_cta=Start+a+free+trial&ref_loc=footer&ref_page=%2Fenterprise"
                  >
                    Start a free trial
                  </Button>

                  <Button
                    as="a"
                    href="/enterprise/contact?ref_cta=Contact+Sales&ref_loc=plans&ref_page=%2Fenterprise&scid=&utm_campaign=Enterprise&utm_content=Enterprise&utm_medium=referral&utm_source=github"
                  >
                    Contact sales
                  </Button>
                </CTABanner.ButtonGroup>
              </CTABanner>
            </Box>

            <Box
              paddingBlockStart={64}
              paddingBlockEnd={32}
              className="enterprise-cards enterprise-center-until-medium"
            >
              <Stack
                direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
                gap="normal"
                padding="none"
              >
                {/* These divs make sure the <Card>s height gets evenly stretched */}
                <div>
                  <Card
                    href="https://docs.github.com/migrations/overview/planning-your-migration-to-github"
                    style={{width: '100%'}}
                  >
                    <Card.Icon icon={<BookIcon />} color="purple" hasBackground />

                    <Card.Heading>Planning your migration to GitHub</Card.Heading>
                  </Card>
                </div>

                <div>
                  <Card
                    href="https://github.com/roadmap-webinar-series"
                    style={{width: '100%'}}
                    ctaText="See what's new"
                  >
                    <Card.Icon icon={<MarkGithubIcon />} color="purple" hasBackground />

                    <Card.Heading>Stay ahead with GitHub’s latest innovations</Card.Heading>
                  </Card>
                </div>

                <div>
                  <Card href="https://resources.github.com/devops/tools/compare/" style={{width: '100%'}}>
                    <Card.Icon icon={<BookIcon />} color="purple" hasBackground />

                    <Card.Heading>Compare GitHub vs. GitLab and other DevOps tools</Card.Heading>
                  </Card>
                </div>
              </Stack>
            </Box>

            <hr className="enterprise-separator my-10" />

            <FAQSection />
          </Box>

          <FootnotesSection />
        </Grid.Column>
      </Grid>
    </ThemeProvider>
  )
}
