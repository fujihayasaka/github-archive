import {SectionIntro, Card, Grid} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function IntegrationSection() {
  return (
    <section id="integration">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">Issues, where you need them</SectionIntro.Heading>

          <SectionIntro.Description>
            Issues can be viewed, created, and managed in your browser, your favorite terminal, or on your phone or
            tablet.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Grid className="lp-Grid">
          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, medium: 6}}>
            <Card className="lp-Card" variant="minimal" href="https://cli.github.com" fullWidth>
              <Card.Image
                className="lp-CardImage"
                src="/images/modules/site/issues/fp24/integration-card-1.webp"
                alt="A terminal view showing issues relevant to the user, including those assigned, mentioning, and opened by the user, categorized by status with accompanying issue numbers and brief descriptions. The image features a gradient background that transitions from purple at the top to a darker shade towards the bottom."
                width={600}
              />

              <Card.Heading size="6">GitHub CLI</Card.Heading>

              <Card.Description>View, update, and create issues without ever leaving your terminal.</Card.Description>
            </Card>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, medium: 6}}>
            <Card className="lp-Card" variant="minimal" href="https://github.com/mobile" fullWidth>
              <Card.Image
                className="lp-CardImage"
                src="/images/modules/site/issues/fp24/integration-card-2.webp"
                alt="Two smartphone screens display GitHub notifications and issue details, with a purple-to-black gradient background. The left screen shows a list of notifications, including issues and pull requests from different repositories like TensorFlow and GitHub's OctoArcade Invaders. The right screen zooms in on a specific issue titled 'Save score across levels,' displaying details of the issue and a comment by user tobiasahlin."
                width={600}
              />

              <Card.Heading size="6">GitHub Mobile</Card.Heading>

              <Card.Description>
                Create and manage issues on the go with our native iOS and Android mobile apps.
              </Card.Description>
            </Card>
          </Grid.Column>
        </Grid>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
