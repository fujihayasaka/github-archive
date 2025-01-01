import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {Grid, RiverBreakout, Text, Timeline, Link} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import type {GenericContent} from '../../../../../brand/lib/types/contentful'

import AutoPlayVideo from '../../_components/AutoPlayVideo'

function renderRichText(richText: RichText) {
  return documentToReactComponents(richText, {
    renderMark: {
      [MARKS.BOLD]: text => <em>{text}</em>,
    },
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => [children],
    },
  })
}

type Props = {
  riverBreakout: GenericContent
}

export function FeaturesRiverBreakout(props: Props) {
  const {riverBreakout} = props
  const {text, links, media, content} = riverBreakout.fields
  const firstLink = links?.at(0)

  const video = media?.find(item => item.fields.id === 'featuresCopilotFeaturesRiverBreakoutVideo')
  const poster = media?.find(item => item.fields.id === 'featuresCopilotFeaturesRiverBreakoutPoster')

  const isPostMsBuildLaunch = isFeatureEnabled('site_msbuild_launch')

  return (
    <Grid.Column span={12}>
      <RiverBreakout className="lp-RiverBreakout">
        <RiverBreakout.Visual className="lp-River-visual">
          {video ? (
            <AutoPlayVideo
              src={video.fields.asset.fields.file.url}
              poster={poster?.fields.asset.fields.file.url || ''}
              width="1248"
              height="647"
              className={`${!isPostMsBuildLaunch ? 'd-none d-md-block ' : ''}lp-RiverBreakout-video--lg`}
              aria-label={video.fields.asset.fields.description}
              darkButton
              analyticsProps={{
                context: 'demo_gif',
                location: 'river_breakout',
              }}
            />
          ) : (
            <></>
          )}
        </RiverBreakout.Visual>

        <RiverBreakout.Content
          trailingComponent={() => (
            <Timeline className="lp-Timeline">
              {content?.map(item => (
                <Timeline.Item key={item.sys.id}>{renderRichText(item.fields.text)}</Timeline.Item>
              ))}
            </Timeline>
          )}
        >
          {text ? (
            <Text style={{maxWidth: 690}}>
              {renderRichText(text)}

              {firstLink ? (
                <span style={{marginTop: '32px', marginBottom: '48px', display: 'block'}}>
                  <Link
                    href={firstLink.fields.href}
                    variant="accent"
                    {...getAnalyticsEvent({
                      action: firstLink.fields.text,
                      tag: 'link',
                      context: 'river_breakout',
                      location: 'features_rivers',
                    })}
                  >
                    {firstLink.fields.text}
                  </Link>
                </span>
              ) : null}
            </Text>
          ) : (
            <></>
          )}
        </RiverBreakout.Content>
      </RiverBreakout>
    </Grid.Column>
  )
}
