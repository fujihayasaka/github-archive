import {SectionIntro, Text, RiverBreakout, Stack, Timeline, Image, Pillar, AnimationProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function DiscussSection() {
  return (
    <section id="discuss" className="fp-Section--isRaised">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <RiverBreakout className="fp-RiverBreakout">
          <RiverBreakout.A11yHeading>Customize</RiverBreakout.A11yHeading>

          <RiverBreakout.Visual>
            <Image
              className="fp-RiverBreakoutVisualImage"
              src="/images/modules/site/discussions/fp24/discuss-river-1.webp"
              alt="Screenshot of the GitHub Discussions page for 'octoinvaders,' showing featured discussions like 'Game dev log,' 'Power-up contest,' and 'Fan Art showcase.' Categories include General, Feedback, and Q&A. The interface has a dark theme with a pink-to-purple gradient background."
              loading="lazy"
            />
          </RiverBreakout.Visual>

          <RiverBreakout.Content
            className="fp-RiverBreakout-content"
            style={{rowGap: '0'}} // Remove gap when 2nd row is unused
            trailingComponent={() => (
              <Timeline>
                <Timeline.Item>
                  <em>Custom categories</em> Create discussion categories that fit your communityʼs needs.
                </Timeline.Item>

                <Timeline.Item>
                  <em>Label and organize</em> Make announcements and the most important discussions more visible for
                  contributors.
                </Timeline.Item>

                <Timeline.Item>
                  <em>Pin discussions</em> Make announcements and the most important discussions more visible for
                  contributors.
                </Timeline.Item>
              </Timeline>
            )}
          >
            <Text>
              <em>
                Personalize for your community and team with any ways to make your space unique for you and your
                collaborators.
              </em>
            </Text>
          </RiverBreakout.Content>
        </RiverBreakout>

        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro">
          <SectionIntro.Heading>Monitor insights</SectionIntro.Heading>

          <SectionIntro.Description>
            Track the health and growth of your community with a dashboard full of actionable data.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <AnimationProvider>
          <Stack
            direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
            gap="spacious"
            padding="none"
          >
            <div style={{margin: '0 auto'}}>
              <div className="lp-PillarVisual">
                <Image
                  className="lp-PillarVisualImage"
                  src="/images/modules/site/discussions/fp24/statement-1.webp"
                  alt="Contribution activity graph"
                  loading="lazy"
                  animate="slide-in-up"
                />
              </div>

              <Pillar>
                <Pillar.Heading>Contribution activity</Pillar.Heading>

                <Pillar.Description>
                  Count of total contribution activity to Discussions, Issues, and PRs.
                </Pillar.Description>
              </Pillar>
            </div>
            <div style={{margin: '0 auto'}}>
              <div className="lp-PillarVisual">
                <Image
                  className="lp-PillarVisualImage"
                  src="/images/modules/site/discussions/fp24/statement-2.webp"
                  alt="Discussions page views graph"
                  loading="lazy"
                  animate="slide-in-up"
                />
              </div>

              <Pillar>
                <Pillar.Heading>Discussions page views</Pillar.Heading>

                <Pillar.Description>
                  Total page views to Discussions segmented by logged in vs anonymous users.
                </Pillar.Description>
              </Pillar>
            </div>

            <div style={{margin: '0 auto'}}>
              <div className="lp-PillarVisual">
                <Image
                  className="lp-PillarVisualImage"
                  src="/images/modules/site/discussions/fp24/statement-3.webp"
                  alt="Discussions daily contributors graph"
                  loading="lazy"
                  animate="slide-in-up"
                />
              </div>

              <Pillar>
                <Pillar.Heading>Discussions daily contributors</Pillar.Heading>

                <Pillar.Description>
                  Count of unique users who have reacted, upvoted, marked an answer, commented, or posted in the
                  selected period.
                </Pillar.Description>
              </Pillar>
            </div>
          </Stack>
        </AnimationProvider>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
