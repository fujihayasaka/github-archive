import {
  Bento,
  Box,
  Grid,
  Heading,
  Label,
  Link,
  River,
  RiverBreakout,
  SectionIntro,
  Text,
  Timeline,
} from '@primer/react-brand'

import {DeviceMobileIcon} from '@primer/octicons-react'
import {analyticsEvent} from '../../../../lib/analytics'
import {Image} from '../../../../components/Image/Image'
import AutoPlayVideo from './AutoPlayVideo'

import FeaturesBreakoutLgVideo from '../_assets/features-breakout.mp4'
import FeaturesBreakoutLgPoster from '../_assets/features-breakout-poster.webp'
import FeaturesBreakoutSmVideo from '../_assets/features-breakout-sm.mp4'
import FeaturesBreakoutSmPoster from '../_assets/features-breakout-poster-sm.webp'

import CopilotNextEditSuggestionImage from '../_assets/copilot-next-edit-suggestion.webp'
import CopilotAgentModeImage from '../_assets/copilot-agent-mode.webp'
import CopilotExtensionsImage from '../_assets/copilot-extensions.webp'
import CopilotMobileImage from '../_assets/copilot-mobile.webp'
import CopilotModelsImage from '../_assets/copilot-models.webp'
import CopilotReviewImage from '../_assets/copilot-review.webp'
import CopilotTerminalLgImage from '../_assets/copilot-terminal.webp'
import CopilotTerminalSmImage from '../_assets/copilot-terminal-sm.webp'
import CopilotTerminalBgImage from '../_assets/copilot-terminal-bg.webp'

import AppStoreImage from '../_assets/app-store.png'
import GooglePlayImage from '../_assets/google-play.png'

export default function FeaturesSection() {
  return (
    <section
      id="features"
      className="lp-Section lp-Section--compact lp-SectionIntro--regular"
      style={{
        position: 'relative',
        zIndex: 1,
        background: 'rgb(13, 17, 23) linear-gradient(180deg, #161B22 0%, #0D1117 25%)',
        paddingTop: 'var(--base-size-96)',
      }}
    >
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
        <Grid.Column span={12}>
          <SectionIntro fullWidth align="center" className="lp-SectionIntro">
            <SectionIntro.Label size="large" className="lp-Label--section">
              Features
            </SectionIntro.Label>
            <SectionIntro.Heading size="2" weight="semibold">
              Customizable. Contextual. <br className="break-whenWide" /> AI-powerful.
            </SectionIntro.Heading>
          </SectionIntro>
        </Grid.Column>

        <Grid.Column span={12}>
          <RiverBreakout className="lp-RiverBreakout">
            <RiverBreakout.Visual className="lp-River-visual">
              <AutoPlayVideo
                src={FeaturesBreakoutLgVideo}
                poster={FeaturesBreakoutLgPoster}
                width="1248"
                height="647"
                className="d-none d-md-block lp-RiverBreakout-video--lg"
                aria-label="Video demonstrating how GitHub Copilot accelerates workflow through interactive codebase chat"
                darkButton
                analyticsProps={{
                  context: 'demo_gif',
                  location: 'river_breakout',
                }}
              />
              <AutoPlayVideo
                src={FeaturesBreakoutSmVideo}
                poster={FeaturesBreakoutSmPoster}
                width="350"
                height="380"
                className="d-block d-md-none lp-RiverBreakout-video--sm"
                aria-label="Video demonstrating how GitHub Copilot accelerates workflow through interactive codebase chat"
                darkButton
                analyticsProps={{
                  context: 'demo_gif',
                  location: 'river_breakout',
                }}
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              trailingComponent={() => (
                <Timeline className="lp-Timeline">
                  <Timeline.Item>
                    <em>Answers that know how you code.</em> GitHub Copilot can use your code and custom instructions to
                    code the way you prefer.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Your AI-powered teammate.</em> From debugging to deployment, GitHub Copilot generates what you
                    need—so you can build faster.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="lp-RiverBreakout-text">
                <em>Create tests, docs, and more.</em> Ask GitHub Copilot a question, get the right answer for you, and
                accept the code with a single click.
                <span style={{marginTop: '32px', marginBottom: '48px', display: 'block'}}>
                  <Link
                    href="https://docs.github.com/en/copilot/example-prompts-for-github-copilot-chat"
                    variant="accent"
                    {...analyticsEvent({
                      action: 'chat_docs',
                      tag: 'link',
                      context: 'copilot_chat_example_prompts',
                      location: 'features',
                    })}
                  >
                    Our favorite Copilot prompts
                  </Link>
                </span>
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <River imageTextRatio="50:50" className="lp-River-mod">
            <River.Visual className="lp-River-visual">
              <Image src={CopilotModelsImage} alt="GitHub Copilot model selection" width="708" height="472" />
            </River.Visual>
            <River.Content>
              <Heading as="h3" size="5">
                Choose your model
              </Heading>
              <Text as="p" variant="muted" className="lp-River-text">
                Use models like Anthropic&apos;s{' '}
                <a
                  className="lp-Link--inline"
                  href="https://docs.github.com/en/copilot/using-github-copilot/using-claude-sonnet-in-github-copilot"
                  {...analyticsEvent({
                    action: 'docs_instructions',
                    tag: 'inline_link',
                    context: 'using_sonnet',
                    location: 'features',
                  })}
                >
                  Claude 3.5 Sonnet
                </a>
                , OpenAI o3, and GPT 4o to tackle coding tasks one minute—then dive into deeper reasoning the next.
              </Text>
            </River.Content>
          </River>

          <River imageTextRatio="50:50" className="lp-River-mod">
            <River.Visual className="lp-River-visual">
              <Image
                src={CopilotAgentModeImage}
                alt="New dropdown selector inside of GitHub Copilot’s chat input to toggle between Agent mode and Edit mode that comes after the voice chat button and before the model dropdown selector."
                width="708"
                height="472"
              />
            </River.Visual>
            <River.Content>
              <Label color="green-blue" className="lp-River-label">
                Preview
              </Label>
              <Heading as="h3" size="5">
                Here, there, and everywhere
              </Heading>
              <Text as="p" variant="muted" className="lp-River-text">
                In agent mode, Copilot gathers context across multiple files, suggests and tests edits, and validates
                changes for your approval, so you can make comprehensive updates with speed and accuracy.
              </Text>
              <Link
                href="https://aka.ms/vscode-copilot-agent"
                variant="accent"
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'link',
                  context: 'agent_mode',
                  location: 'features',
                })}
              >
                Try agent mode today
              </Link>
            </River.Content>
          </River>

          <River imageTextRatio="50:50" className="lp-River-mod">
            <River.Visual className="lp-River-visual">
              <Image
                src={CopilotNextEditSuggestionImage}
                alt="Active popover above the arrow button indicator in front of a line of code with the options: Go To/Accept (tab key), Reject (escape key), Feedback, and Settings."
                width="708"
                height="472"
              />
            </River.Visual>
            <River.Content>
              <Label color="green-blue" className="lp-River-label">
                Preview
              </Label>
              <Heading as="h3" size="5">
                Thank you, next
              </Heading>
              <Text as="p" variant="muted" className="lp-River-text">
                With next edit suggestions, GitHub Copilot predicts and adapts to your workflow—helping you code faster
                with less manual editing.
              </Text>
              <Link
                href="https://aka.ms/gh-copilot-nes-docs"
                variant="accent"
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'link',
                  context: 'next_edit_suggestions',
                  location: 'features',
                })}
              >
                Try next edit suggestions
              </Link>
            </River.Content>
          </River>

          <River imageTextRatio="50:50" className="lp-River-mod">
            <River.Visual className="lp-River-visual">
              <a
                href="https://github.com/features/preview/copilot-code-review"
                tabIndex={-1}
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'image',
                  context: 'copilot_review',
                  location: 'features',
                })}
              >
                <Image
                  src={CopilotReviewImage}
                  alt="GitHub Copilot performing a code review"
                  width="708"
                  height="472"
                />
              </a>
            </River.Visual>
            <River.Content>
              <Heading as="h3" size="5">
                Instant feedback
              </Heading>
              <Text as="p" variant="muted" className="lp-River-text">
                Ask GitHub Copilot to review your work, uncover hidden bugs, fix mistakes, and more—before you get a
                human review.
              </Text>
              <Link
                href="https://github.com/features/preview/copilot-code-review"
                variant="accent"
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'link',
                  context: 'copilot_review',
                  location: 'features',
                })}
              >
                Get early access
              </Link>
            </River.Content>
          </River>

          <River imageTextRatio="50:50" className="lp-River-mod">
            <River.Visual className="lp-River-visual">
              <a
                href="https://github.com/features/copilot/extensions"
                tabIndex={-1}
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'image',
                  context: 'copilot_extensions',
                  location: 'features',
                })}
              >
                <Image
                  src={CopilotExtensionsImage}
                  alt="GitHub Copilot Extensions for Azure, Datastax, Docker, MongoDB and Sentry"
                  width="708"
                  height="472"
                />
              </a>
            </River.Visual>
            <River.Content>
              <Heading as="h3" size="5">
                Extensions for your favorite tools
              </Heading>
              <Text as="p" variant="muted" className="lp-River-text">
                Check logs, create feature flags, and deploy apps—all from Copilot Chat, enhanced by an ecosystem of
                extensions from third party tools and services.
              </Text>
              <Link
                href="https://github.com/features/copilot/extensions"
                variant="accent"
                {...analyticsEvent({
                  action: 'docs_instructions',
                  tag: 'link',
                  context: 'copilot_extensions',
                  location: 'features',
                })}
              >
                Explore GitHub Copilot Extensions
              </Link>
            </River.Content>
          </River>
        </Grid.Column>

        {/* Spacer */}
        <Box paddingBlockStart={48} aria-hidden />

        <Grid.Column span={12}>
          <Bento className="Bento Bento--raised">
            <Bento.Item columnSpan={12} colorMode="dark" style={{gridRowEnd: 'auto'}} className="position-relative">
              <Bento.Content
                padding={{
                  xsmall: 'normal',
                  medium: 'spacious',
                }}
                horizontalAlign="center"
                className="position-relative z-1"
              >
                <Bento.Heading
                  as="h3"
                  size="3"
                  weight="semibold"
                  className="text-center mt-2 mt-md-0"
                  style={{maxWidth: '660px'}}
                >
                  Ask for assistance right in your terminal
                </Bento.Heading>

                <Link
                  href="https://docs.github.com/copilot/using-github-copilot/using-github-copilot-in-the-command-line"
                  size="large"
                  variant="default"
                  {...analyticsEvent({action: 'cli_docs', tag: 'link', context: 'terminal', location: 'features'})}
                >
                  Try Copilot in the CLI
                </Link>
              </Bento.Content>

              <Bento.Visual fillMedia={false} className="lp-Features-terminal-visual">
                <Image
                  src={CopilotTerminalLgImage}
                  alt="Screenshot of GitHub Copilot CLI in a terminal"
                  width="831"
                  height="369"
                  className="lp-Features-terminal-visual-img d-none d-md-block mx-auto"
                />

                <Image
                  src={CopilotTerminalSmImage}
                  alt="Screenshot of GitHub Copilot CLI in a terminal"
                  width="558"
                  height="369"
                  className="lp-Features-terminal-visual-img d-block d-md-none ml-auto"
                />

                <Image
                  src={CopilotTerminalBgImage}
                  alt=""
                  width="1248"
                  height="620"
                  className="lp-Features-terminal-bg"
                  aria-hidden
                />
              </Bento.Visual>
            </Bento.Item>

            <Bento.Item
              columnSpan={{xsmall: 12, medium: 5, large: 5, xlarge: 5}}
              rowSpan={{xsmall: 4, small: 4, medium: 4, xlarge: 5}}
              className="Bento-item"
            >
              <Bento.Content
                horizontalAlign={{xsmall: 'center', large: 'start'}}
                padding={{xsmall: 'normal', xlarge: 'spacious'}}
                leadingVisual={<DeviceMobileIcon />}
                className="lp-Features-mobile"
              >
                <Bento.Heading as="h3" size="4" weight="semibold" className="lp-Features-mobileText">
                  Chat with your AI pair programmer on-the-go
                </Bento.Heading>
              </Bento.Content>
              <Bento.Visual
                padding={{xsmall: 'normal', xlarge: 'spacious'}}
                fillMedia={false}
                horizontalAlign="center"
                verticalAlign="end"
                style={{columnGap: '24px', flexWrap: 'wrap'}}
              >
                <a
                  href="https://play.google.com/store/apps/details?id=com.github.android"
                  target="_blank"
                  rel="noreferrer"
                  {...analyticsEvent({
                    action: 'play_store',
                    tag: 'button',
                    context: 'mobile_apps',
                    location: 'features',
                  })}
                >
                  <Image
                    src={GooglePlayImage}
                    alt="Download GitHub on the Google Play Store"
                    width="180"
                    height="53"
                    style={{display: 'block'}}
                  />
                </a>
                <a
                  href="https://apps.apple.com/app/github/id1477376905?ls=1"
                  target="_blank"
                  rel="noreferrer"
                  {...analyticsEvent({
                    action: 'app_store',
                    tag: 'button',
                    context: 'mobile_apps',
                    location: 'features',
                  })}
                >
                  <Image
                    src={AppStoreImage}
                    alt="Download GitHub on the Apple App Store"
                    width="179"
                    height="53"
                    style={{display: 'block'}}
                  />
                </a>
              </Bento.Visual>
            </Bento.Item>

            <Bento.Item
              columnSpan={{xsmall: 12, medium: 7, large: 7, xlarge: 7}}
              rowSpan={{xsmall: 4, small: 3, medium: 4, xlarge: 5}}
            >
              <Bento.Visual position="25% 0%">
                <Image
                  src={CopilotMobileImage}
                  alt="A phone showing GitHub Copilot in GitHub Mobile"
                  width="724"
                  height="560"
                />
              </Bento.Visual>
            </Bento.Item>
          </Bento>
        </Grid.Column>
      </Grid>
    </section>
  )
}
