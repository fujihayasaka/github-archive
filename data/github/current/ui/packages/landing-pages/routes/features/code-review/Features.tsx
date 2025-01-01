import {Image, Text, Link, SectionIntro, River, Heading, AnimationProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features" className="fp-Section--isRaised">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">See every update and act on it, in-situ</SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="64px" size1012="96px" />

        <AnimationProvider>
          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/code-review/fp24/features-river-1.webp"
                alt="Screenshot showing a code diff in a file named head.scss. The removed lines are min-height: 40px; and padding: 10px;. The added lines are position: sticky;, top: 0;, and padding: 20px. The background has a pink-to-purple gradient."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h3">Diffs</Heading>

              <Text size="200">
                Preview changes in context with your code to see what is being proposed. Side-by-side Diffs highlight
                added, edited, and deleted code right next to the original file, so you can easily spot changes.
              </Text>

              <Link
                href="https://docs.github.com/articles/about-comparing-branches-in-pull-requests/"
                variant="default"
              >
                Learn more
              </Link>
            </River.Content>
          </River>

          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/code-review/fp24/features-river-2.webp"
                alt="Screenshot of two commits added, and the changes were approved. The background has a pink-to-purple gradient."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h3">History</Heading>

              <Text size="200">
                Browse commits, comments, and references related to your pull request in a timeline-style interface.
                Your pull request will also highlight what’s changed since you last checked.
              </Text>

              <Link href="https://docs.github.com/articles/searching-commits/" variant="default">
                Learn more
              </Link>
            </River.Content>
          </River>

          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/code-review/fp24/features-river-3.webp"
                alt="Image showing a file history showing four version entries with names and timestamps: 'First draft' and 'delete old pricing,' modified over the past few months."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h3">Blame</Heading>

              <Text size="200">
                See what a file looked like before a particular change. With blame view, you can see how any portion of
                your file has evolved over time without viewing the file’s full history.
              </Text>

              <Link href="https://docs.github.com/articles/tracing-changes-in-a-file/" variant="default">
                Learn more
              </Link>
            </River.Content>
          </River>
        </AnimationProvider>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
