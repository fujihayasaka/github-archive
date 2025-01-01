import {Card, Grid, SectionIntro, Stack} from '@primer/react-brand'
import {BookIcon, MegaphoneIcon, MarkGithubIcon} from '@primer/octicons-react'
import {analyticsEvent} from '../../../../lib/analytics'

export default function ResourcesSection() {
  return (
    <section id="resources" className="lp-Section lp-Section--compact lp-SectionIntro--compact">
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
        <Grid.Column span={12}>
          <SectionIntro fullWidth align="center" className="lp-SectionIntro">
            <SectionIntro.Heading size="3" weight="semibold">
              Get the most out of GitHub Copilot
            </SectionIntro.Heading>
          </SectionIntro>

          <Stack
            direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
            gap="normal"
            padding="none"
          >
            <div className="lp-Resources-card">
              <Card
                ctaText="See previews"
                href="https://github.com/features/preview"
                {...analyticsEvent({
                  action: 'features_preview',
                  tag: 'link',
                  context: 'previews_card',
                  location: 'additional_resources',
                })}
              >
                <Card.Icon icon={<MegaphoneIcon />} color="purple" hasBackground />
                <Card.Heading>Preview the latest features</Card.Heading>
                <Card.Description>Be the first to explore what’s next for GitHub Copilot.</Card.Description>
              </Card>
            </div>

            <div className="lp-Resources-card">
              <Card
                ctaText="See what's new"
                href="https://github.com/roadmap-webinar-series"
                {...analyticsEvent({
                  action: 'roadmap_webinar_series',
                  tag: 'link',
                  context: 'roadmap_webinar_series_card',
                  location: 'additional_resources',
                })}
              >
                <Card.Icon icon={<MarkGithubIcon />} color="purple" hasBackground />
                <Card.Heading>Stay ahead with GitHub’s latest innovations</Card.Heading>
                <Card.Description>
                  See how our recent and upcoming releases can help your organization drive efficiency, security, and
                  innovation.
                </Card.Description>
              </Card>
            </div>

            <div className="lp-Resources-card">
              <Card
                ctaText="Go to Trust Center"
                href="https://copilot.github.trust.page/"
                {...analyticsEvent({
                  action: 'trust_center',
                  tag: 'link',
                  context: 'trust_center_card',
                  location: 'additional_resources',
                })}
              >
                <Card.Icon icon={<BookIcon />} color="purple" hasBackground />
                <Card.Heading>Visit the GitHub Copilot Trust Center</Card.Heading>
                <Card.Description>
                  Gain peace of mind with our security, privacy, and responsible AI policies.
                </Card.Description>
              </Card>
            </div>
          </Stack>
        </Grid.Column>
      </Grid>
    </section>
  )
}
