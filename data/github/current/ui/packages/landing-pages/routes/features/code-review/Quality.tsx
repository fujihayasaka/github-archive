import {ThemeProvider, SectionIntro, Grid, Card, CTABanner, Button} from '@primer/react-brand'
import {CheckCircleIcon, GitBranchIcon, PersonAddIcon} from '@primer/octicons-react'

import {Spacer} from '../components/Spacer'

export default function QualitySection() {
  return (
    <section id="quality" className="fp-Section--isRaised">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">Merge the highest quality code</SectionIntro.Heading>

          <SectionIntro.Description>
            Reviews can improve your code, but mistakes happen. Limit human error and ensure only high quality code gets
            merged with detailed permissions and status checks.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Grid className="lp-Grid">
          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, large: 4}}>
            <Card
              className="lp-Card fp-gradientBorder"
              ctaText="See plan options"
              href="https://github.com/pricing"
              fullWidth
            >
              <Card.Icon icon={<PersonAddIcon />} color="purple" />

              <Card.Heading size="6">Fast, relevant results</Card.Heading>

              <Card.Description>
                Give collaborators as much access as they need through your repository settings. You can extend access
                to a few teams and select which ones can read or write to your files. The options you have for
                permissions depend on your plan.
              </Card.Description>
            </Card>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, large: 4}}>
            <Card
              className="lp-Card fp-gradientBorder"
              ctaText="Learn more"
              href="https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches"
              fullWidth
            >
              <Card.Icon icon={<GitBranchIcon />} color="purple" />

              <Card.Heading size="6">Protected branches</Card.Heading>

              <Card.Description>
                Protected Branches help you maintain the integrity of your code. Limit who can push to a branch, and
                disable force pushes to specific branches. Then scale your policies with the Protected Branches API.
              </Card.Description>
            </Card>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn" span={{xsmall: 12, large: 4}}>
            <Card
              className="lp-Card fp-gradientBorder"
              ctaText="Status API doc"
              href="https://docs.github.com/rest/commits/statuses"
              fullWidth
            >
              <Card.Icon icon={<CheckCircleIcon />} color="purple" />

              <Card.Heading size="6">Required status checks</Card.Heading>

              <Card.Description>
                Create required status checks to add an extra layer of error prevention on branches. Use the Status API
                to enforce checks and disable the merge button until they pass. To err is human; to automate, divine!
              </Card.Description>
            </Card>
          </Grid.Column>
        </Grid>

        <Spacer size="64px" size1012="128px" />

        <ThemeProvider colorMode="dark" style={{backgroundColor: 'transparent'}}>
          <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
            <CTABanner.Heading size="2">Every change starts with a pull request.</CTABanner.Heading>

            <CTABanner.ButtonGroup buttonsAs="a">
              <Button href="/pricing">Get started</Button>

              <Button href="/enterprise/contact?ref_cta=Contact+sales&ref_loc=cta-banner&ref_page=%2Ffeatures%2Fcode-review&utm_content=Platform&utm_medium=site&utm_source=github">
                Contact sales
              </Button>
            </CTABanner.ButtonGroup>
          </CTABanner>
        </ThemeProvider>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
