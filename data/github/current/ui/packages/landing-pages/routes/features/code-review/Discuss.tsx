import {Image, Text, Link, SectionIntro, River, Heading} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function DiscussSection() {
  return (
    <section id="discuss">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">
            Discuss code <br className="fp-breakWhenWide" /> within your code
          </SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="64px" size1012="96px" />

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-review/fp24/discuss-river-1.webp"
              alt="Image showing a file history showing four version entries with names and timestamps: 'First draft' and 'delete old pricing,' modified over the past few months. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h3">Comments</Heading>

            <Text size="200">
              On GitHub, conversations happen alongside your code. Leave detailed comments on code syntax and ask
              questions about structure inline.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-review/fp24/discuss-river-2.webp"
              alt="Dropdown menu showing a request for a review with options to select users. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h3">Review requests</Heading>

            <Text size="200">
              If you’re on the other side of the code, requesting peer reviews is easy. Add users to your pull request,
              and they’ll receive a notification letting them know you need their feedback.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-review/fp24/discuss-river-3.webp"
              alt="Notification indicating that a review is required before changes can be made, with a user requested for the review. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h3">Reviews</Heading>

            <Text size="200">
              Save your teammates a few notifications. Bundle your comments into one cohesive review, then specify
              whether comments are required changes or just suggestions.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-review/fp24/discuss-river-4.webp"
              alt="Alert indicating a branch conflict with files that need to be resolved before merging. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h3">Resolve simple conflicts</Heading>

            <Text size="200">
              You can’t always avoid conflict. Merge pull requests faster by resolving simple merge conflicts on
              GitHub—no command line necessary.
            </Text>

            <Link href="https://docs.github.com/articles/resolving-a-merge-conflict-on-github/">
              Learn how to resolve merge conflicts
            </Link>
          </River.Content>
        </River>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
