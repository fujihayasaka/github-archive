import type {BoxSpacingValues} from '@primer/react-brand'
import {Box, Grid} from '@primer/react-brand'

import type {FlexPage} from '../../../schemas/contentful/contentTypes/flexTemplate'
import {ContentfulBackgroundImage} from '../../../components/contentful/ContentfulBackgroundImage/ContentfulBackgroundImage'
import {ContentfulHero} from '../../../components/contentful/ContentfulHero/ContentfulHero'
import {ContentfulBreadcrumbs} from '../../../components/contentful/ContentfulBreadcrumbs/ContentfulBreadcrumbs'
import {ContentfulSubnav} from '../../../components/contentful/ContentfulSubnav/ContentfulSubnav'

type SpacingValues = (typeof BoxSpacingValues)[number]

const heroPaddingValues: Record<string, SpacingValues> = {
  condensed: 80,
  spacious: 128,
  none: 'none',
}

export function FlexTemplateHero({page}: {page: FlexPage}) {
  const {breadcrumbs, hero, heroBackgroundImage, subnav, visualSettings} = page.fields.template.fields

  const subNavColorMode = heroBackgroundImage?.fields.colorMode || page.fields.settings?.fields.colorMode
  const hasBackgroundImage = !!heroBackgroundImage
  const hasSubnav = !!subnav

  const heroPaddingBlockEnd = visualSettings?.fields.heroPaddingBlockEnd
    ? heroPaddingValues[visualSettings.fields.heroPaddingBlockEnd]
    : undefined

  return (
    <>
      {subnav && (
        <ContentfulSubnav component={subnav} data-color-mode={subNavColorMode} hasShadow linkVariant="default" />
      )}

      <Grid>
        <Grid.Column>
          <ContentfulBackgroundImage component={heroBackgroundImage}>
            <Box paddingBlockStart={hasBackgroundImage && hasSubnav ? 64 : undefined}>
              {breadcrumbs && (
                <Box paddingBlockStart={hasBackgroundImage && hasSubnav ? 16 : hasSubnav ? 80 : 32}>
                  <ContentfulBreadcrumbs breadcrumbs={breadcrumbs} />
                </Box>
              )}
              <ContentfulHero data-hpc component={hero} paddingBlockEnd={heroPaddingBlockEnd} />
            </Box>
          </ContentfulBackgroundImage>
        </Grid.Column>
      </Grid>
    </>
  )
}
