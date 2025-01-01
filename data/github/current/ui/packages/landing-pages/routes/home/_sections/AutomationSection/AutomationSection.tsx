import {useRef} from 'react'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'

import {Grid, Heading, Image, Link, Pillar, Text} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {ContentfulInlineFootnote} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnote'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'

import type {GenericSectionWithIds, GenericGroup, GenericContent} from '../../../../brand/lib/types/contentful'

import type Assets from '../../webgl-utils/assets'

import SectionHero from '../../components/SectionHero/SectionHero'
import SectionIntro from '../../components/SectionIntro/SectionIntro'

import {RiverAccordion} from '../../_components/RiverAccordion/RiverAccordion'

const ANALYTICS_ID = 'automation'

type Props = {
  contentfulContent: GenericSectionWithIds
  assetsRef: React.RefObject<Assets>
}

export function AutomationSection(props: Props) {
  const {contentfulContent, assetsRef} = props

  const {sectionIntro} = contentfulContent.fields

  const {automationSectionBreakout, automationSectionRiverAccordion} = contentfulContent.ids as {
    automationSectionBreakout: GenericContent
    automationSectionRiverAccordion: GenericGroup
  }

  const breakoutVideo = automationSectionBreakout.fields.media?.find(
    item => item.fields.id === 'automationSectionBreakoutVideo',
  )

  const breakoutVideoPoster = automationSectionBreakout.fields.media?.find(
    item => item.fields.id === 'automationSectionBreakoutVideoPoster',
  )

  const accordionItems = automationSectionRiverAccordion.fields.content
    ? (automationSectionRiverAccordion.fields.content as GenericContent[]).map(item => {
        const {heading, subheading, links, media} = item.fields
        const firstImage = media?.at(0)
        const firstLink = links?.at(0)

        return {
          title: heading || '',
          description: subheading ? documentToPlainTextString(subheading) : '',
          link: {
            label: firstLink?.fields.text || '',
            url: firstLink?.fields.href || '',
          },
          visual: {
            url: firstImage?.fields.asset.fields.file.url || '',
            alt: firstImage?.fields.description || '',
          },
        }
      })
    : []

  const mainGridRef = useRef<HTMLDivElement | null>(null)
  const {isIntersecting: isMainGridInView} = useIntersectionObserver(mainGridRef, {threshold: 0.33, isOnce: true})

  function renderRichText(richText: RichText, fontSize: '300' | '400' = '400') {
    return documentToReactComponents(richText, {
      renderMark: {
        [MARKS.BOLD]: text => (
          <Text as="span" size={fontSize} variant="default">
            {text}
          </Text>
        ),
      },
      renderNode: {
        [BLOCKS.PARAGRAPH]: (_, children) => (
          <Text as="span" size={fontSize} variant="muted">
            {children}
          </Text>
        ),
        [INLINES.EMBEDDED_ENTRY]: node => {
          if (node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
            return <ContentfulInlineFootnote component={node.data.target} analyticsLocation={ANALYTICS_ID} />
          }

          return null
        },
      },
    })
  }

  return (
    <section id="automation" className="lp-Section">
      <div className="lp-SectionTemplate">
        <div className="lp-SectionBlock">
          <div className="lp-SectionBlock-content">
            {sectionIntro ? (
              <SectionIntro
                title={documentToPlainTextString(sectionIntro.fields.heading)}
                description={
                  sectionIntro.fields.description ? documentToPlainTextString(sectionIntro.fields.description) : ''
                }
                mascot="copilot"
                assetsRef={assetsRef}
                isWebGLMascotOnly
              />
            ) : null}

            {breakoutVideo ? (
              <SectionHero
                analyticsId={ANALYTICS_ID}
                isCopilotUI
                hasPlayButton
                playButtonAriaLabel={{
                  play: 'Play video',
                  pause: 'Pause video',
                }}
                visuals={[
                  {
                    type: 'video',
                    url: {
                      desktop: breakoutVideo.fields.asset.fields.file.url,
                    },
                    poster: {
                      desktop: breakoutVideoPoster ? breakoutVideoPoster.fields.asset.fields.file.url : '',
                    },
                    alt: breakoutVideo.fields.description ? breakoutVideo.fields.description : '',
                  },
                ]}
              />
            ) : null}
          </div>
        </div>

        {automationSectionBreakout ? (
          <div className="lp-SectionBlock">
            <div ref={mainGridRef} className="lp-SectionBlock-content lp-SectionBlock-content--lines">
              <Grid className={`lp-SectionTemplate-grid ${!isMainGridInView ? 'lp-SectionTemplate-grid--hidden' : ''}`}>
                <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: 7}}>
                  <div className="lp-SectionTemplate-content">
                    {automationSectionBreakout.fields.text ? (
                      <Heading as="h3" size="6" weight="semibold">
                        {renderRichText(automationSectionBreakout.fields.text)}
                      </Heading>
                    ) : null}

                    {automationSectionBreakout.fields.links ? (
                      <div>
                        <Link
                          href={automationSectionBreakout.fields.links[0]?.fields.href}
                          variant="accent"
                          className="lp-SectionTemplate-content-link"
                          {...getAnalyticsEvent({
                            action: automationSectionBreakout.fields.links[0]?.fields.text || '',
                            tag: 'link',
                            context: 'content',
                            location: ANALYTICS_ID,
                          })}
                        >
                          <Text weight="normal" size="300">
                            {automationSectionBreakout.fields.links[0]?.fields.text}
                          </Text>
                        </Link>
                      </div>
                    ) : null}
                  </div>
                </Grid.Column>

                {automationSectionBreakout.fields.content ? (
                  <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: 5}}>
                    {(automationSectionBreakout.fields.content as GenericContent[]).map(item => (
                      <div key={item.sys.id} className="lp-SectionTemplate-customer">
                        <Pillar>
                          {item.fields.media ? (
                            <Pillar.Icon
                              className="lp-SectionTemplate-customer-logo"
                              icon={
                                <Image
                                  src={item.fields.media[0]?.fields.asset.fields.file.url || ''}
                                  alt={item.fields.media[0]?.fields.description || ''}
                                  height={32}
                                  loading="lazy"
                                />
                              }
                            />
                          ) : null}

                          {item.fields.text ? (
                            <Pillar.Description className="lp-SectionTemplate-customer-description">
                              {renderRichText(item.fields.text, '300')}
                            </Pillar.Description>
                          ) : null}

                          {item.fields.links ? (
                            <Pillar.Link
                              className="lp-SectionTemplate-customer-link"
                              href={item.fields.links[0]?.fields.href || ''}
                              {...getAnalyticsEvent({
                                action: item.fields.links[0]?.fields.text || '',
                                tag: 'link',
                                context: 'customers',
                                location: ANALYTICS_ID,
                              })}
                            >
                              <Text weight="normal" size="300">
                                {item.fields.links[0]?.fields.text}
                              </Text>
                            </Pillar.Link>
                          ) : null}
                        </Pillar>
                      </div>
                    ))}
                  </Grid.Column>
                ) : null}
              </Grid>
            </div>
          </div>
        ) : null}

        {accordionItems.length > 0 ? <RiverAccordion items={accordionItems} analyticsId={ANALYTICS_ID} /> : null}
      </div>
    </section>
  )
}
