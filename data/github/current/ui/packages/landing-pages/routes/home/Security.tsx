import {BreakpointSize, Grid, Pillar, Image, Statistic, Text, useWindowSize} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import SectionHero from './components/SectionHero/SectionHero'
import SectionIntro from './components/SectionIntro/SectionIntro'
import FootnoteLink from './components/FootnoteLink/FootnoteLink'

import {useEffect, useMemo, useRef, useState} from 'react'
import useIntersectionObserver from '../../lib/hooks/useIntersectionObserver'
import {COPY, HERO_VISUALS} from './Security.data'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from './utils/responsive'
import type Assets from './webgl-utils/assets'

export default function Security({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
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

  const hasEmptyCell = useMemo(
    () =>
      (windowSize.currentBreakpointSize === BreakpointSize.MEDIUM && COPY.topics.length % 2 !== 0) ||
      ([BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ) &&
        COPY.topics.length % 3 !== 0),
    [windowSize],
  )

  const statisticsDOM = useMemo(() => {
    const WrapperElement = hasEmptyCell ? 'div' : Grid

    return (
      <WrapperElement
        {...(hasEmptyCell ? {} : {className: `Security-grid ${!isMainGridInView ? 'Security-grid--hidden' : ''}`})}
      >
        {COPY.statistics.map((statistic, index) => (
          <Grid.Column
            className="Security-gridColumn Security-gridColumn--half Security-gridColumn--centered"
            span={{xsmall: 12, medium: 6}}
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`statistic_${index}`}
          >
            <div>
              <Statistic>
                <Statistic.Heading className="Security-statisticHeading" size="600">
                  {statistic.heading}
                </Statistic.Heading>

                <Statistic.Description className="Security-statisticDescription">
                  {/* eslint-disable-next-line react/no-danger */}
                  <span dangerouslySetInnerHTML={{__html: statistic.description}} />
                  {statistic.footnote && <FootnoteLink number={statistic.footnote} />}
                </Statistic.Description>
              </Statistic>
            </div>
          </Grid.Column>
        ))}
      </WrapperElement>
    )
  }, [hasEmptyCell, isMainGridInView])

  return (
    <section id="security" className="lp-Section">
      <div className="lp-SectionBlock">
        <div className="lp-SectionBlock-content">
          <SectionIntro
            mascot="shield"
            title={COPY.intro.title}
            description={COPY.intro.description}
            assetsRef={assetsRef}
            isWebGLMascotOnly
          />

          <SectionHero
            visuals={HERO_VISUALS}
            playButtonAriaLabel={COPY.hero.aria.playButton}
            text={{
              title: COPY.hero.title,
              description: COPY.hero.description,
              link: {
                url: COPY.hero.link.url,
                label: COPY.hero.link.label,
              },
            }}
            analyticsId={COPY.analyticsId}
          />
        </div>
      </div>

      <div className="lp-SectionBlock">
        <div ref={mainGridRef} className="lp-SectionBlock-content lp-SectionBlock-content--lines">
          <Grid
            className={`Security-grid Security-grid--hasPillars ${!isMainGridInView ? 'Security-grid--hidden' : ''}`}
          >
            {COPY.topics.map((topic, index) => (
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
                    <Pillar.Description className="Security-pillarDescription">
                      <Text size="300">
                        <span>{topic.title}</span>
                        {topic.description}
                      </Text>
                    </Pillar.Description>

                    <Pillar.Link
                      href={topic.link.url}
                      {...getAnalyticsEvent({
                        action: topic.link.label,
                        tag: 'link',
                        context: topic.title,
                        location: COPY.analyticsId,
                      })}
                    >
                      <Text weight="normal">{topic.link.label}</Text>
                    </Pillar.Link>
                  </Pillar>

                  <div className="Security-gridImageContainer">
                    <Image
                      className="Security-gridImage"
                      src={topic.visual.url}
                      alt={topic.visual.alt}
                      loading="lazy"
                    />
                  </div>
                </div>
              </Grid.Column>
            ))}

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
