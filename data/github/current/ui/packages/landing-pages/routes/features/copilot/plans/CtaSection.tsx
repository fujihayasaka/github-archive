import {Box, Button, Grid, Stack, Text} from '@primer/react-brand'

import {ContentfulSectionIntro} from '@github-ui/swp-core/components/contentful/ContentfulSectionIntro'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import type {GenericContent, GenericSectionWithIds} from '../../../../brand/lib/types/contentful'

import IdeList from '../_components/IdeList'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function CtaSection(props: Props) {
  const {contentfulContent} = props

  const {sectionIntro} = contentfulContent.fields

  const {featuresCopilotPlansCta} = contentfulContent.ids as {
    featuresCopilotPlansCta: GenericContent
  }

  const ctaLink = featuresCopilotPlansCta.fields.links?.at(0)

  return (
    <Grid as="section" className="lp-Section pt-5 pt-lg-8 pb-8">
      <Grid.Column span={{xsmall: 12, small: 8}} start={{xsmall: 1, small: 3}}>
        <Stack direction="vertical" gap={40} className="text-center p-0">
          {sectionIntro ? (
            <ContentfulSectionIntro component={sectionIntro} fullWidth headingSize="3" className="p-0" />
          ) : null}

          <IdeList type="big" location="pricing-cta" />

          {featuresCopilotPlansCta ? (
            <Box>
              <Text size="300" weight="normal" variant="muted">
                {featuresCopilotPlansCta.fields.heading}
              </Text>

              {ctaLink ? (
                <Box marginBlockStart={24}>
                  <Button
                    as="a"
                    href={ctaLink.fields.href}
                    variant="subtle"
                    className="lp-Features-secondaryButton"
                    {...getAnalyticsEvent({
                      action: ctaLink.fields.text,
                      tag: 'button',
                      context: 'ide_list',
                      location: 'cta',
                    })}
                  >
                    {ctaLink.fields.text}
                  </Button>
                </Box>
              ) : null}
            </Box>
          ) : null}
        </Stack>
      </Grid.Column>
    </Grid>
  )
}
