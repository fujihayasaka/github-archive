import {Box, Button, Grid, SectionIntro, Stack, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'
import IdeList from './IdeList'

interface CallToActionProps {
  copilotContactSalesPath: string
}

export default function CallToAction({copilotContactSalesPath}: CallToActionProps) {
  return (
    <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
      <Grid.Column span={12}>
        <Stack direction="vertical" gap={40} className="text-center p-0">
          <SectionIntro align="center" fullWidth className="p-0">
            <SectionIntro.Label size="large" className="lp-SectionIntro-label">
              Getting started
            </SectionIntro.Label>
            <SectionIntro.Heading size="3" weight="semibold">
              Start using Copilot in your IDE
            </SectionIntro.Heading>
          </SectionIntro>

          <IdeList type="big" location="pricing-cta" />

          <Box>
            <Text size="300" weight="normal" variant="muted">
              Need human help? Let’s define how to propel your team into a new era.
            </Text>

            <Box marginBlockStart={24}>
              <Button
                as="a"
                href={copilotContactSalesPath}
                variant="secondary"
                className="lp-Features-secondaryButton"
                {...analyticsEvent({
                  action: 'contact_sales',
                  tag: 'button',
                  context: 'need_help',
                  location: 'cta',
                })}
              >
                Contact sales
              </Button>
            </Box>
          </Box>
        </Stack>
      </Grid.Column>
    </Grid>
  )
}
