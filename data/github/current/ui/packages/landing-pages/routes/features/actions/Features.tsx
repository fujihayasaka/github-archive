import {
  AnimationProvider,
  Grid,
  Heading,
  Image,
  Link,
  Pillar,
  River,
  RiverBreakout,
  SectionIntro,
  Text,
  Timeline,
} from '@primer/react-brand'

import {BookIcon, HeartIcon, KeyIcon, LogIcon, PackageIcon, StackIcon} from '@primer/octicons-react'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">
            Kick off workflows on any <br className="fp-breakWhenWide" /> GitHub event to automate tasks
          </SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <AnimationProvider>
          <Grid className="lp-Grid">
            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<PackageIcon />} color="green" />

                <Pillar.Heading>Hosted runners for every major OS</Pillar.Heading>

                <Pillar.Description>
                  Linux, macOS, Windows, ARM, GPU, and containers make it easy to build and test all your projects. Run
                  directly on a VM or inside a container. Use your own VMs, in the cloud or on-prem, with self-hosted
                  runners.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<HeartIcon />} color="green" />

                <Pillar.Heading>Matrix builds</Pillar.Heading>

                <Pillar.Description>
                  Save time with matrix workflows that simultaneously test across multiple operating systems and
                  versions of your runtime.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<BookIcon />} color="green" />

                <Pillar.Heading>Any language</Pillar.Heading>

                <Pillar.Description>
                  GitHub Actions supports Node.js, Python, Java, Ruby, PHP, Go, Rust, .NET, and more. Build, test, and
                  deploy applications in your language of choice.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<LogIcon />} color="green" />

                <Pillar.Heading>Live logs</Pillar.Heading>

                <Pillar.Description>
                  See your workflow run in realtime with color and emoji. It’s one click to copy a link that highlights
                  a specific line number to share a CI/CD failure.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<KeyIcon />} color="green" />

                <Pillar.Heading>Built in secret store</Pillar.Heading>

                <Pillar.Description>
                  Automate your software development practices with workflow files embracing the Git flow by codifying
                  it in your repository.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6, large: 4}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<StackIcon />} color="green" />

                <Pillar.Heading>Multi-container testing</Pillar.Heading>

                <Pillar.Description>
                  Test your web service and its DB in your workflow by simply adding some docker-compose to your
                  workflow file.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>
          </Grid>
        </AnimationProvider>

        <Spacer size="64px" size1012="128px" />

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/actions/fp24/features-river-1.webp"
              alt="Screenshot showing the results of a successful GitHub Actions workflow. The header indicates that 'All checks have passed,' with three successful checks listed below. The checks include 'Build,' which completed successfully in 42 seconds, 'Test,' which completed in 5 minutes, and 'Code scanning / CodeQL,' which completed in 30 seconds. Each check has a corresponding 'Details' link. At the bottom, there is a green 'Merge pull request' button, indicating that the pull request is ready to be merged. The background features a gradient from green to teal."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h2" size="4">
              Run a workflow on <br className="fp-breakWhenWide" /> any GitHub event
            </Heading>

            <Text>
              Whether you want to build a container, deploy a web service, or automate welcoming new users to your open
              source projects—thereʼs an action for that. Pair GitHub Packages with Actions to simplify package
              management, including version updates, fast distribution with our global CDN, and dependency resolution,
              using your existing GITHUB_TOKEN.
            </Text>
          </River.Content>
        </River>

        <Spacer size="64px" size1012="128px" />

        <RiverBreakout className="fp-RiverBreakout">
          <RiverBreakout.A11yHeading>Actions marketplace</RiverBreakout.A11yHeading>

          <RiverBreakout.Visual>
            <Image
              className="fp-RiverBreakoutVisualImage"
              src="/images/modules/site/actions/fp24/features-river-breakout.webp"
              alt="Screenshot of a GitHub Actions workflow file being edited. The cursor is in the 'on' section of the YAML file, with a dropdown menu showing various triggers such as push, issue_creation, new_release, workflow_dispatch, and others. The code includes steps to set up a Node.js environment and run tests. On the right side of the screen, there is a 'Marketplace' panel displaying featured actions like 'Setup Node.js environment,' 'Setup Java JDK,' 'Setup .NET Core SDK,' and 'Download a Build Artifact.' The background features a gradient from green to blue."
              loading="lazy"
            />
          </RiverBreakout.Visual>

          <RiverBreakout.Content
            className="fp-RiverBreakout-content"
            trailingComponent={() => (
              <Timeline>
                <Timeline.Item>
                  <em>Easily deploy to any cloud, create tickets in Jira, or publish a package to npm.</em>
                </Timeline.Item>

                <Timeline.Item>
                  <em>Want to venture off the beaten path?</em> Use the millions of open source libraries available on
                  GitHub to create your own actions. Write them in JavaScript or create a container action—both can
                  interact with the full GitHub API and any other public API.
                </Timeline.Item>
              </Timeline>
            )}
          >
            <Text>
              <em>GitHub Actions connects all of your tools</em> to automate every step of your development workflow.
            </Text>

            <Link
              className="fp-RiverBreakout-link"
              href="https://github.com/marketplace?type=actions"
              variant="default"
            >
              Explore the actions marketplace
            </Link>
          </RiverBreakout.Content>
        </RiverBreakout>

        <Spacer size="64px" size1012="128px" />

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/actions/fp24/features-river-2.webp"
              alt="Screenshot of a terminal window showing Docker commands to log in to GitHub's container registry (ghcr.io), tag an application image, and push the image version (1.0.0) to the repository, with a successful login and digest confirmation. The background features a gradient from purple to green."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Heading as="h2" size="4">
              Secure Package Registry for Code and Workflows
            </Heading>

            <Text>
              Securely store and manage your code and packages with GitHub credentials, integrated into your workflows
              via APIs and webhooks. Enjoy fast, reliable downloads through a global CDN for optimized performance.
            </Text>

            <Link href="https://docs.github.com/packages" variant="default">
              Read the docs
            </Link>
          </River.Content>
        </River>
      </div>
    </section>
  )
}
