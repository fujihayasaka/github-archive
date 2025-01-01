import {Bento, Link, Pillar, Stack, Timeline} from '@primer/react-brand'
import {Image} from '../../components/Image/Image'
import {analyticsEvent} from '../../lib/analytics'
import GradientIssueOpenOcticon from './assets/gradient-issue-open-octicon.svg'
import GradientIssueClosedOcticon from './assets/gradient-issue-closed-octicon.svg'
import GradientInfoOcticon from './assets/gradient-info-octicon.svg'

export function CustomerStoryBento() {
  return (
    <Bento.Item
      columnSpan={12}
      rowSpan={{
        xsmall: 12,
        small: 12,
        medium: 7,
      }}
      flow={{
        xsmall: 'row',
        small: 'row',
        medium: 'column',
      }}
      style={{background: 'var(--base-color-scale-black-0)', gridGap: 0, gridRow: 'auto'}}
      className="customer-story-bento"
    >
      <Bento.Visual padding={{xsmall: 'normal', medium: 'spacious'}} className="d-block customer-story-bento-padding">
        <Bento.Heading
          as="h3"
          size="4"
          weight="semibold"
          data-analytics-visible='{"category":"copilot customer story","label":"ref_cta:copilot_customer_story;ref_loc:body"}'
        >
          Duolingo empowers its engineers to be force multipliers for expertise with GitHub Copilot and GitHub
          Codespaces.
        </Bento.Heading>
        <Link
          href="https://github.com/customer-stories/duolingo"
          variant="accent"
          size="large"
          className="mb-8 mb-lg-10 mt-6"
          {...analyticsEvent({action: 'story', tag: 'link', context: 'duolingo_bento', location: 'enterprise_ready'})}
        >
          Read customer story
        </Link>
        <Stack
          direction="horizontal"
          className="customer-story-pillars"
          justifyContent="flex-start"
          gap="spacious"
          style={{padding: '0'}}
        >
          <Pillar className="flex-1">
            <Pillar.Heading size="4" weight="medium">
              ~25%
            </Pillar.Heading>
            <Pillar.Description className="mb-0">Increase in developer speed with GitHub Copilot</Pillar.Description>
          </Pillar>
          <div className="customer-story-pillar-divider" />
          <Pillar className="flex-1">
            <Pillar.Heading size="4" weight="medium">
              1m
            </Pillar.Heading>
            <Pillar.Description className="mb-0">Set-up time for largest repo with Codespaces</Pillar.Description>
          </Pillar>
        </Stack>
      </Bento.Visual>
      <Bento.Visual padding={{xsmall: 'normal', medium: 'spacious'}} className="customer-story-bento-padding">
        <Timeline>
          <Timeline.Item className="customer-story-timeline-item">
            <Pillar>
              <Pillar.Heading className="customer-story-timeline-heading">
                <Image
                  src={GradientIssueOpenOcticon}
                  alt=""
                  width="24"
                  height="24"
                  className="customer-story-timeline-octicon"
                />
                Problem
              </Pillar.Heading>
              <Pillar.Description className="enterprise-lp">
                Inconsistent standards and workflows limited developer mobility and efficiency, limiting Duolingo’s
                ability to expand its content and deliver on its core mission.
              </Pillar.Description>
            </Pillar>
          </Timeline.Item>
          <Timeline.Item className="customer-story-timeline-item">
            <Pillar>
              <Pillar.Heading className="customer-story-timeline-heading">
                <Image
                  src={GradientIssueClosedOcticon}
                  alt=""
                  width="24"
                  height="24"
                  className="customer-story-timeline-octicon"
                />
                Solution
              </Pillar.Heading>
              <Pillar.Description className="enterprise-lp">
                GitHub Copilot, GitHub Codespaces, and custom API integrations enforce code consistency, accelerate
                developer speed, and remove the barriers to using engineering as a force multiplier for expertise.
              </Pillar.Description>
            </Pillar>
          </Timeline.Item>
          <Timeline.Item className="customer-story-timeline-item">
            <Pillar>
              <Pillar.Heading className="customer-story-timeline-heading">
                <Image
                  src={GradientInfoOcticon}
                  alt=""
                  width="24"
                  height="24"
                  className="customer-story-timeline-octicon"
                />
                Products
              </Pillar.Heading>
              <Pillar.Description className="enterprise-lp">
                <Pillar.Link
                  href="/enterprise"
                  className="customer-story-bento-link"
                  {...analyticsEvent({
                    action: 'enterprise',
                    tag: 'link',
                    context: 'duolingo_bento',
                    location: 'enterprise_ready',
                  })}
                >
                  GitHub Enterprise
                </Pillar.Link>
                <br />
                <Pillar.Link
                  href="/features/codespaces"
                  className="customer-story-bento-link"
                  {...analyticsEvent({
                    action: 'codespaces',
                    tag: 'link',
                    context: 'duolingo_bento',
                    location: 'enterprise_ready',
                  })}
                >
                  GitHub Codespaces
                </Pillar.Link>
                <br />
                <Pillar.Link
                  href="/features/copilot"
                  className="customer-story-bento-link"
                  {...analyticsEvent({
                    action: 'copilot',
                    tag: 'link',
                    context: 'duolingo_bento',
                    location: 'enterprise_ready',
                  })}
                >
                  GitHub Copilot
                </Pillar.Link>
              </Pillar.Description>
            </Pillar>
          </Timeline.Item>
        </Timeline>
      </Bento.Visual>
    </Bento.Item>
  )
}
