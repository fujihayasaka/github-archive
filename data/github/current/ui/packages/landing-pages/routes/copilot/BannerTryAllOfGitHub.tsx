import {Button, Text, Heading, Grid} from '@primer/react-brand'
import {analyticsEvent} from '../../lib/analytics'

interface BannerTryAllOfGitHub {
  copilotForBusinessSignupPath: string
}

export function BannerTryAllOfGitHub({copilotForBusinessSignupPath}: BannerTryAllOfGitHub) {
  return (
    <div className="m-6 pt-4 pb-6" style={{backgroundColor: 'var(--base-color-scale-gray-7)', borderRadius: '8px'}}>
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap position-relative">
        <Grid.Column span={6} className="position-relative">
          <Heading as="h3" size="5">
            Try Copilot with all of GitHub.
            <br />
            Free for 30 days.
          </Heading>
        </Grid.Column>
        <Grid.Column span={6} className="position-relative pr-6">
          <Text as="p" size="200" weight="normal" variant="muted" className="pb-4">
            We get it, there&apos;s a lot you can do with GitHub. That’s why we&apos;ve packed all of it into a single
            risk-free trial — including Copilot Business.
          </Text>
          <Button
            as="a"
            href={copilotForBusinessSignupPath}
            style={{backgroundColor: 'var(--base-color-scale-gray-5)'}}
            hasArrow={false}
            {...analyticsEvent({
              action: 'try_all_of_github',
              tag: 'button',
              context: 'copilot_business_plan',
              location: 'offer_cards',
            })}
          >
            Try all of GitHub
          </Button>
        </Grid.Column>
      </Grid>
    </div>
  )
}
