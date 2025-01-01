import {useRef} from 'react'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'

import {Grid, Heading, Link, Text} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {ContentfulInlineFootnote} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnote'
import {ContentfulTestimonial} from '@github-ui/swp-core/components/contentful/ContentfulTestimonial'
import type {PrimerComponentTestimonial} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentTestimonial'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'

import type {GenericSectionWithIds, GenericGroup, GenericContent} from '../../../../brand/lib/types/contentful'

import type Assets from '../../webgl-utils/assets'

import SectionHero from '../../components/SectionHero/SectionHero'
import SectionIntro from '../../components/SectionIntro/SectionIntro'

import {RiverAccordion} from '../../_components/RiverAccordion/RiverAccordion'

const ANALYTICS_ID = 'collaboration'

type Props = {
  contentfulContent: GenericSectionWithIds
  assetsRef: React.RefObject<Assets>
}

export function CollaborationSection(props: Props) {
  const {contentfulContent, assetsRef} = props

  const {sectionIntro} = contentfulContent.fields

  const {collaborationSectionBreakout, collaborationSectionRiverAccordion} = contentfulContent.ids as {
    collaborationSectionBreakout: GenericContent
    collaborationSectionRiverAccordion: GenericGroup
  }

  const breakoutImage = collaborationSectionBreakout.fields.media?.find(
    item => item.fields.id === 'collaborationSectionBreakoutImage',
  )

  const testimonial = collaborationSectionBreakout.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentTestimonial',
  ) as PrimerComponentTestimonial | undefined

  const accordionItems = collaborationSectionRiverAccordion.fields.content
    ? (collaborationSectionRiverAccordion.fields.content as GenericContent[]).map(item => {
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
    <section id="collaboration" className="lp-Section">
      <div className="lp-SectionTemplate">
        <div className="lp-SectionBlock">
          <div className="lp-SectionBlock-content">
            {sectionIntro ? (
              <SectionIntro
                title={documentToPlainTextString(sectionIntro.fields.heading)}
                description={
                  sectionIntro.fields.description ? documentToPlainTextString(sectionIntro.fields.description) : ''
                }
                mascot="mona"
                assetsRef={assetsRef}
                isWebGLMascotOnly
              />
            ) : null}

            {breakoutImage ? (
              <SectionHero
                analyticsId={ANALYTICS_ID}
                visuals={[
                  {
                    type: 'image',
                    url: {
                      desktop: breakoutImage.fields.asset.fields.file.url,
                    },
                    alt: breakoutImage.fields.description ? breakoutImage.fields.description : '',
                  },
                ]}
              />
            ) : null}
          </div>
        </div>

        {collaborationSectionBreakout ? (
          <div className="lp-SectionBlock">
            <div ref={mainGridRef} className="lp-SectionBlock-content lp-SectionBlock-content--lines">
              <Grid className={`lp-SectionTemplate-grid ${!isMainGridInView ? 'lp-SectionTemplate-grid--hidden' : ''}`}>
                <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: 6}}>
                  <div className="lp-SectionTemplate-content">
                    {collaborationSectionBreakout.fields.text ? (
                      <Heading as="h3" size="6" weight="semibold">
                        {renderRichText(collaborationSectionBreakout.fields.text)}
                      </Heading>
                    ) : null}

                    {collaborationSectionBreakout.fields.links ? (
                      <div>
                        <Link
                          href={collaborationSectionBreakout.fields.links[0]?.fields.href}
                          variant="accent"
                          className="lp-SectionTemplate-content-link"
                          {...getAnalyticsEvent({
                            action: collaborationSectionBreakout.fields.links[0]?.fields.text || '',
                            tag: 'link',
                            context: 'content',
                            location: ANALYTICS_ID,
                          })}
                        >
                          <Text weight="normal" size="300">
                            {collaborationSectionBreakout.fields.links[0]?.fields.text}
                          </Text>
                        </Link>
                      </div>
                    ) : null}
                  </div>
                </Grid.Column>

                {testimonial ? (
                  <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: 6}}>
                    <div className="lp-SectionTemplate-testimonial">
                      <ContentfulTestimonial component={testimonial} />
                    </div>
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
