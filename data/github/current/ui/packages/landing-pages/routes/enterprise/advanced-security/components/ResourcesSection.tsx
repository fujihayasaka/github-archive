import {BookIcon} from '@primer/octicons-react'
import {Card, SectionIntro, Stack} from '@primer/react-brand'

export default function ResourcesSection() {
  return (
    <section id="resources" className="lp-Section--resources">
      <div className="lp-Container">
        <div className="lp-Spacer" style={{'--lp-space': '64px', '--lp-space-xl': '104px'}} aria-hidden />

        <SectionIntro align="center" fullWidth>
          <SectionIntro.Heading size="3">
            Get the most out of <br className="lp-break-whenWide" /> GitHub Advanced Security
          </SectionIntro.Heading>
        </SectionIntro>

        <div className="lp-Spacer" style={{'--lp-space': '40px'}} aria-hidden />

        <Stack direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}} gap="normal" padding="none">
          <div className="lp-Resources-card">
            <Card
              ctaText="Get started now"
              href="https://docs.github.com/code-security/getting-started/github-security-features"
            >
              <Card.Icon icon={<BookIcon />} color="blue" hasBackground />
              <Card.Heading>How to get started with GitHub Advanced Security</Card.Heading>
              <Card.Description>Discover how the AppSec solution can benefit your organization.</Card.Description>
            </Card>
          </div>
          <div className="lp-Resources-card">
            <Card
              ctaText="Read the Forrester Report"
              href="https://resources.github.com/forrester-industry-spotlight-github-advanced-security/"
            >
              <Card.Icon icon={<BookIcon />} color="blue" hasBackground />
              <Card.Heading>GitHub TEI spotlight for GitHub Advanced Security</Card.Heading>
              <Card.Description>
                Explore the benefits of improving software security standards in organizations.
              </Card.Description>
            </Card>
          </div>
          <div className="lp-Resources-card">
            <Card
              ctaText="Watch the videos"
              href="https://github.com/enterprise/advanced-security/what-is-github-advanced-security"
            >
              <Card.Icon icon={<BookIcon />} color="blue" hasBackground />
              <Card.Heading>Expert strategies for using GitHub Advanced Security</Card.Heading>
              <Card.Description>
                Learn how industry experts use GitHub Advanced Security to protect their code without sacrificing
                developer productivity.
              </Card.Description>
            </Card>
          </div>
        </Stack>
      </div>
    </section>
  )
}
