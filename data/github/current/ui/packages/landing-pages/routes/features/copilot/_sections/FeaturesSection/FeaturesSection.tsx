import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Box, Grid, SectionIntro} from '@primer/react-brand'

import type {GenericContent, GenericGroup, GenericSectionWithIds} from '../../../../../brand/lib/types/contentful'

import {FeaturesRiver} from './FeaturesRiver'
import {FeaturesRiverBreakout} from './FeaturesRiverBreakout'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function FeaturesSection(props: Props) {
  const {contentfulContent} = props
  const {sectionIntro} = contentfulContent.fields
  const {featuresCopilotFeaturesRiverBreakout, featuresCopilotFeaturesRivers} = contentfulContent.ids as {
    featuresCopilotFeaturesRiverBreakout: GenericContent
    featuresCopilotFeaturesRivers: GenericGroup
  }

  const isPostMsBuildLaunch = isFeatureEnabled('site_msbuild_launch')

  return (
    <section
      id="features"
      className="lp-Section lp-Section--compact lp-SectionIntro--compact"
      style={{
        position: 'relative',
        zIndex: 1,
        background: !isPostMsBuildLaunch ? 'linear-gradient(180deg, #161B22 0%, #000 33.33%)' : '',
      }}
    >
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
        <Grid.Column span={12}>
          {sectionIntro ? (
            <SectionIntro fullWidth align="center" className="lp-SectionIntro">
              {sectionIntro.fields.label ? (
                <SectionIntro.Label>{sectionIntro.fields.label.fields.text}</SectionIntro.Label>
              ) : null}

              <SectionIntro.Heading size="2" weight="semibold">
                {documentToReactComponents(sectionIntro.fields.heading, {
                  renderMark: {
                    [MARKS.BOLD]: text => <em>{text}</em>,
                  },
                  renderNode: {
                    [BLOCKS.PARAGRAPH]: (_, children) => [children, <br key="line-break" />],
                  },
                })}
              </SectionIntro.Heading>
            </SectionIntro>
          ) : null}

          {featuresCopilotFeaturesRiverBreakout ? (
            <FeaturesRiverBreakout riverBreakout={featuresCopilotFeaturesRiverBreakout} />
          ) : null}

          <Box paddingBlockStart={48} aria-hidden />

          {featuresCopilotFeaturesRivers && featuresCopilotFeaturesRivers.fields.content ? (
            <>
              {(featuresCopilotFeaturesRivers.fields.content as GenericContent[]).map(riverItem => (
                <FeaturesRiver key={riverItem.sys.id} river={riverItem} />
              ))}
            </>
          ) : null}
        </Grid.Column>
      </Grid>
    </section>
  )
}
