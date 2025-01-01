import {useEffect, useMemo, useRef, useState} from 'react'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'

import {BreakpointSize, Grid, Pillar, Image, Statistic, Text, useWindowSize, InlineLink} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {ContentfulInlineFootnote} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnote'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'

import type {GenericSectionWithIds, GenericGroup, GenericContent} from '../../../../brand/lib/types/contentful'

import SectionHero from '../../components/SectionHero/SectionHero'
import SectionIntro from '../../components/SectionIntro/SectionIntro'

import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../utils/responsive'
import type Assets from '../../webgl-utils/assets'

const ANALYTICS_ID = 'security'

function renderRichText(richText: RichText) {
  return documentToReactComponents(richText, {
    renderMark: {
      [MARKS.BOLD]: text => (
        <Text as="span" size="300" variant="default">
          {text}
        </Text>
      ),
    },
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => (
        <Text as="span" size="300" variant="muted">
          {children}
        </Text>
      ),
      [INLINES.HYPERLINK]: (node, children) => (
        <InlineLink
          href={node.data.uri}
          {...getAnalyticsEvent({
            action: documentToPlainTextString(node, ' '),
            tag: 'link',
            context: ANALYTICS_ID,
            location: ANALYTICS_ID,
          })}
        >
          {children}
        </InlineLink>
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

type Props = {
  contentfulContent: GenericSectionWithIds
  assetsRef: React.RefObject<Assets>
}

export function SecuritySection(props: Props) {
  const {contentfulContent, assetsRef} = props

  const {sectionIntro} = contentfulContent.fields

  const {securitySectionBreakout, securitySectionFeatures, securitySectionStats} = contentfulContent.ids as {
    securitySectionBreakout: GenericContent
    securitySectionFeatures: GenericGroup
    securitySectionStats: GenericGroup
  }

  const mainGridRef = useRef<HTMLDivElement | null>(null)
  const gridColumnContentRefs = useRef<Array<HTMLDivElement | null>>([])

  const windowSize = useWindowSize()

  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )

  const isSmallHeight = useMemo(
    () => (windowSize?.height && windowSize.height < BREAKPOINT_DESKTOP_MIN_HEIGHT) || false,
    [windowSize],
  )

  const {isIntersecting: isMainGridInView} = useIntersectionObserver(
    mainGridRef,
    {
      threshold: {mobile: 0, desktop: 0.4},
      isOnce: true,
    },
    !isSmallHeight && isDesktopView,
  )

  // Mobile: Reveal each column separately
  const observeColumns = !isSmallHeight && !isDesktopView
  const observerRef = useRef<IntersectionObserver | undefined>(undefined)
  const [allColumnsRevealed, setAllColumnsRevealed] = useState(false)

  useEffect(() => {
    if (!observeColumns || allColumnsRevealed) return

    const revealedElements = new Set<Element>()
    const totalColumns = gridColumnContentRefs.current.filter(Boolean).length

    observerRef.current = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.remove('Security-grid--hiddenOnMobile')
            revealedElements.add(entry.target)

            if (revealedElements.size === totalColumns) {
              observerRef.current?.disconnect()
              setAllColumnsRevealed(true)
            }
          }
        }
      },
      {
        threshold: 0.2,
      },
    )

    for (const ref of gridColumnContentRefs.current) {
      if (ref) {
        observerRef.current.observe(ref)
      }
    }

    return () => observerRef.current?.disconnect()
  }, [observeColumns, allColumnsRevealed])

  const featuresCount =
    securitySectionFeatures && securitySectionFeatures.fields.content
      ? securitySectionFeatures.fields.content.length
      : 0

  const hasEmptyCell = useMemo(
    () =>
      (windowSize.currentBreakpointSize === BreakpointSize.MEDIUM && featuresCount % 2 !== 0) ||
      ([BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ) &&
        featuresCount % 3 !== 0),
    [windowSize, featuresCount],
  )

  const statisticsDOM = useMemo(() => {
    const WrapperElement = hasEmptyCell ? 'div' : Grid

    return (
      <WrapperElement
        {...(hasEmptyCell ? {} : {className: `Security-grid ${!isMainGridInView ? 'Security-grid--hidden' : ''}`})}
      >
        {securitySectionStats
          ? (securitySectionStats.fields.content as GenericContent[]).map((item, index) => (
              <Grid.Column
                className="Security-gridColumn Security-gridColumn--half Security-gridColumn--centered"
                span={{xsmall: 12, medium: 6}}
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`statistic_${index}`}
              >
                <div>
                  <Statistic>
                    {item.fields.heading ? (
                      <Statistic.Heading className="Security-statisticHeading" size="600">
                        {item.fields.heading}
                      </Statistic.Heading>
                    ) : null}

                    {item.fields.subheading ? (
                      <Statistic.Description className="Security-statisticDescription">
                        {renderRichText(item.fields.subheading)}
                      </Statistic.Description>
                    ) : null}
                  </Statistic>
                </div>
              </Grid.Column>
            ))
          : null}
      </WrapperElement>
    )
  }, [hasEmptyCell, isMainGridInView, securitySectionStats])

  return (
    <section id="security" className="lp-Section">
      <div className="lp-SectionBlock">
        <div className="lp-SectionBlock-content">
          {sectionIntro ? (
            <SectionIntro
              title={documentToPlainTextString(sectionIntro.fields.heading)}
              description={
                sectionIntro.fields.description ? documentToPlainTextString(sectionIntro.fields.description) : ''
              }
              mascot="shield"
              assetsRef={assetsRef}
              isWebGLMascotOnly
            />
          ) : null}

          {securitySectionBreakout ? (
            <SectionHero
              analyticsId={ANALYTICS_ID}
              text={{
                title: securitySectionBreakout.fields.heading || '',
                description: securitySectionBreakout.fields.subheading
                  ? documentToPlainTextString(securitySectionBreakout.fields.subheading)
                  : '',
                link: {
                  url: securitySectionBreakout.fields.links?.[0]?.fields.href || '',
                  label: securitySectionBreakout.fields.links?.[0]?.fields.text || '',
                },
              }}
              visuals={[
                {
                  type: 'image',
                  url: {
                    desktop: securitySectionBreakout.fields.media?.[0]?.fields.asset.fields.file.url || '',
                  },
                  alt: securitySectionBreakout.fields.media?.[0]?.fields.description || '',
                },
              ]}
            />
          ) : null}
        </div>
      </div>

      <div className="lp-SectionBlock">
        <div ref={mainGridRef} className="lp-SectionBlock-content lp-SectionBlock-content--lines">
          <Grid
            className={`Security-grid Security-grid--hasPillars ${!isMainGridInView ? 'Security-grid--hidden' : ''}`}
          >
            {securitySectionFeatures
              ? (securitySectionFeatures.fields.content as GenericContent[]).map((item, index) => (
                  <Grid.Column
                    className="Security-gridColumn"
                    span={{xsmall: 12, medium: 6, large: 4}}
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    key={`topic_${index}`}
                  >
                    <div
                      ref={el => {
                        gridColumnContentRefs.current[index] = el
                      }}
                      className={!isSmallHeight ? 'Security-grid--hiddenOnMobile' : ''}
                    >
                      <Pillar>
                        {item.fields.text ? (
                          <Pillar.Description className="Security-pillarDescription">
                            {renderRichText(item.fields.text)}
                          </Pillar.Description>
                        ) : null}

                        {item.fields.links ? (
                          <Pillar.Link
                            href={item.fields.links[0]?.fields.href || ''}
                            variant="accent"
                            className="lp-SectionTemplate-content-link"
                            {...getAnalyticsEvent({
                              action: item.fields.links[0]?.fields.text || '',
                              tag: 'link',
                              context: 'features',
                              location: ANALYTICS_ID,
                            })}
                          >
                            <Text weight="normal">{item.fields.links[0]?.fields.text}</Text>
                          </Pillar.Link>
                        ) : null}
                      </Pillar>

                      {item.fields.media?.[0] ? (
                        <div className="Security-gridImageContainer">
                          <Image
                            className="Security-gridImage"
                            src={item.fields.media?.[0].fields.asset.fields.file.url || ''}
                            alt={item.fields.media?.[0].fields.description || ''}
                            loading="lazy"
                          />
                        </div>
                      ) : null}
                    </div>
                  </Grid.Column>
                ))
              : null}

            {hasEmptyCell && (
              <Grid.Column
                className="Security-gridColumn Security-gridColumn--statistics"
                span={{xsmall: 12, medium: 6, large: 4}}
              >
                {statisticsDOM}
              </Grid.Column>
            )}
          </Grid>

          {!hasEmptyCell && statisticsDOM}
        </div>
      </div>
    </section>
  )
}
