import {SectionIntro, Pillar, Grid, AnimationProvider} from '@primer/react-brand'

import {BugIcon, DatabaseIcon, DeviceMobileIcon, ZapIcon} from '@primer/octicons-react'

import {Spacer} from '../components/Spacer'

export default function ContextSection() {
  return (
    <section id="context">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">What you can do with Codespaces</SectionIntro.Heading>

          <SectionIntro.Link
            href="https://github.blog/2021-08-11-githubs-engineering-team-moved-codespaces/"
            variant="default"
          >
            Learn how GitHub builds with Codespaces
          </SectionIntro.Link>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <AnimationProvider>
          <Grid className="lp-Grid">
            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<DeviceMobileIcon />} color="green" />

                <Pillar.Heading size="5">Code from any device</Pillar.Heading>

                <Pillar.Description>
                  Want to code on an iPad? Go for it. Spin up Codespaces from any device with internet access. Don’t
                  worry if your device is powerful enough—Codespaces lives in the cloud.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<ZapIcon />} color="green" />

                <Pillar.Heading size="5">Onboard at the speed of thought</Pillar.Heading>

                <Pillar.Description>
                  No more building your dev environment while you onboard. Codespaces launches instantly from any
                  repository on GitHub with pre-configured, secure environments.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<DatabaseIcon />} color="green" />

                <Pillar.Heading size="5">Streamline contractor onboarding</Pillar.Heading>

                <Pillar.Description>
                  Codespaces gives you control over how your consultants access your resources, while providing them
                  with instant onboarding and a fluid developer experience.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>

            <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 6}}>
              <Pillar animate="slide-in-up">
                <Pillar.Icon icon={<BugIcon />} color="green" />

                <Pillar.Heading size="5">Fix bugs right from a pull request</Pillar.Heading>

                <Pillar.Description>
                  Got a pull request detailing a bug or security issue? Open Codespaces right from the pull request
                  without waiting for your dev environment to load.
                </Pillar.Description>
              </Pillar>
            </Grid.Column>
          </Grid>
        </AnimationProvider>
      </div>
    </section>
  )
}
