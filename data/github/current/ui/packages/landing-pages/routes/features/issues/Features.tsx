import {Image, River, Heading, Text, Timeline, AnimationProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="56px" size1012="112px" />

        <AnimationProvider>
          <River className="fp-River" align="end">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/issues/fp24/features-river-1.webp"
                alt="Display of task tracking within an issue, showing the status of related tasks and their connection to the main issue. The background has a pink-to-purple gradient."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h3" size="4">
                Break issues into <br className="fp-breakWhenWide" /> actionable tasks
              </Heading>

              <Text>
                Tackle complex issues with task lists and track their status with new progress indicators. Convert tasks
                into their own issues and navigate your work hierarchy.
              </Text>
            </River.Content>
          </River>

          <River className="fp-River" align="end">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/issues/fp24/features-river-2.webp"
                alt="An issue discussion displaying a series of comments and tasks related to improving alien character controls, including updates from multiple team members. The background has a pink-to-purple gradient."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h3" size="4">
                Move conversations forward
              </Heading>

              <Text>
                Express ideas with GitHub Flavored Markdown, mention contributors, react with emoji, clarify with
                attachments, and see references from commits, pull requests, releases, and deploys. Coordinate by
                assigning contributors and teams, or by adding them to milestones and projects. All in a single
                timeline.
                <Timeline className="lp-TimelineInRiver">
                  <Timeline.Item>Upload and attach videos to comments</Timeline.Item>

                  <Timeline.Item>Dive into work faster with issue forms and templates</Timeline.Item>
                </Timeline>
              </Text>
            </River.Content>
          </River>
        </AnimationProvider>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
