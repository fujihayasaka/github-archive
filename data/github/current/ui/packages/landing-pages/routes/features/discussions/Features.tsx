import {SectionIntro, Text, River, Image} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features">
      <div className="fp-Section-container">
        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">Dedicated space for conversations</SectionIntro.Heading>

          <SectionIntro.Description>
            Decrease the burden of managing active work in issues and pull requests by providing a separate space to
            host ongoing discussions, questions, and ideas.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="64px" size1012="96px" />

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/discussions/fp24/features-river-1.webp"
              alt="Screenshot of a GitHub Discussion where JohnCreek asks for game power-up ideas, and tonyjaramillo's reply suggesting 'Hubot' as a sidekick is marked as the accepted answer. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Mark what’s most helpful.</strong> Highlight quality responses and make the best answer more
              discoverable for future community members to find.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/discussions/fp24/features-river-2.webp"
              alt="Screenshot of a GitHub Discussions thread where enstyled suggests a power-up idea involving Hubot revealing a path and protecting Mona. The post has received 5 upvotes and several reactions. Below, pifafu and tobiasahlin add to the discussion, suggesting Hubot could provide different power-ups depending on levels and appreciating the collaboration idea. The background has a gradient from pink to purple."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Thread conversations.</strong> Keep context in-tact and conversations on track with threaded
              comments.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/discussions/fp24/features-river-3.webp"
              alt="Screenshot of a GitHub poll created by JohnCreek titled 'Power-up contest.' The poll asks participants to choose their favorite power-up idea for Mona in a game. The poll is part of a discussion in the 'Feedback' category, and the background features a gradient from pink to purple."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Ask your community with polls.</strong> Gauge interest in a feature, vote on a meetup time, or
              learn more about your community with custom polls.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/discussions/fp24/features-river-4.webp"
              alt="Screenshot of a Slack-like interface named 'OctoSlack' with the #community channel selected. The right panel displays a community feed from GitHub Discussions, where Robotoocat announces a new poll created by johncreek titled 'Power-up contest.' The message includes a snippet of the poll description and a link to the discussion. Robotoocat also notes that ajashams voted in the poll. The interface features a purple-to-pink gradient background."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Leverage GraphQL API and webhooks.</strong> Decrease maintainer burden by integrating your
              workflows where your teams already are.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/discussions/fp24/features-river-5.webp"
              alt="Screenshot of a closed GitHub issue titled 'Gameplay improvements #1192.' CameronFoxly suggests adding power-ups, and Johncreek proposes taking the discussion to the community. The post has likes and reactions. The background has a pink-to-purple gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold" style={{color: 'var(--brand-color-text-default'}}>
              <strong>Give your open ended conversations the room they need outside of issues.</strong> Convert
              discussions into issues when you’re ready to scope out work.
            </Text>
          </River.Content>
        </River>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
