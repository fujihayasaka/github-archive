import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'

import {Grid, Stack, Pillar} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {ContentfulSectionIntro} from '@github-ui/swp-core/components/contentful/ContentfulSectionIntro'

import type {GenericContent, GenericSectionWithIds} from '../../../../../brand/lib/types/contentful'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function IntegrationsSection(props: Props) {
  const {contentfulContent} = props
  const {sectionIntro, content} = contentfulContent.fields

  return (
    <section className="lp-Section lp-Section--compact lp-SectionIntro--compact">
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap">
        <Grid.Column span={12}>
          {sectionIntro ? (
            <ContentfulSectionIntro component={sectionIntro} fullWidth headingSize="3" className="lp-SectionIntro" />
          ) : null}

          <Stack
            direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
            gap="spacious"
            padding="none"
          >
            {content
              ? (content as GenericContent[]).map(item => (
                  <Pillar style={{maxWidth: '100%'}} key={item.sys.id}>
                    {item.fields.media && item.fields.media[0] ? (
                      <Pillar.Image
                        src={item.fields.media[0].fields.asset.fields.file.url}
                        alt={item.fields.media[0].fields.description || ''}
                      />
                    ) : null}

                    {item.fields.heading ? <Pillar.Heading>{item.fields.heading}</Pillar.Heading> : null}

                    {item.fields.text ? (
                      <Pillar.Description>
                        {documentToReactComponents(item.fields.text, {
                          renderMark: {
                            [MARKS.BOLD]: text => <em>{text}</em>,
                          },
                          renderNode: {
                            [BLOCKS.PARAGRAPH]: (_, children) => [children],
                          },
                        })}
                      </Pillar.Description>
                    ) : null}

                    {item.fields.links && item.fields.links[0] ? (
                      <Pillar.Link
                        href={item.fields.links[0].fields.href}
                        {...getAnalyticsEvent({
                          action: item.fields.links[0].fields.text,
                          tag: 'link',
                          context: item.fields.heading || 'integrations_pillar',
                          location: 'integrations',
                        })}
                      >
                        {item.fields.links[0].fields.text}
                      </Pillar.Link>
                    ) : null}
                  </Pillar>
                ))
              : null}
          </Stack>
        </Grid.Column>
      </Grid>
    </section>
  )
}
