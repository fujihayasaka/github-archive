import {Box, Button, Grid, Stack, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../lib/analytics'

interface CallToActionProps {
  copilotContactSalesPath: string
}

export function CallToAction({copilotContactSalesPath}: CallToActionProps) {
  return (
    <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
      <Grid.Column span={12}>
        <div className="lp-ConicGradientBorder">
          <Stack direction="vertical" className="lp-Pricing-item lp-CallToAction-bg text-center z-1 position-relative">
            <Text size="500">Need human help?</Text>
            <Text size="300" weight="normal" variant="muted">
              Let’s define how to propel your team into a new era.
            </Text>
            <Box marginBlockStart={16}>
              <Button
                as="a"
                href={copilotContactSalesPath}
                variant="secondary"
                className="lp-Features-secondaryButton"
                {...analyticsEvent({
                  action: 'contact_sales',
                  tag: 'button',
                  context: 'need_help',
                  location: 'features_table',
                })}
              >
                Contact sales
              </Button>
            </Box>
          </Stack>
        </div>
      </Grid.Column>
    </Grid>
  )
}
