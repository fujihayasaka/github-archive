import {BreakpointSize, Grid, Pillar, Image, Statistic, Text, useWindowSize} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import SectionHero from './components/SectionHero/SectionHero'
import SectionIntro from './components/SectionIntro/SectionIntro'
import useFootnotes from './hooks/useFootnotes'
import Footnote from './components/Footnote/Footnote'
import FootnoteToggle from './components/Footnote/FootnoteToggle/FootnoteToggle'
import {useEffect, useMemo, useRef, useState} from 'react'
import useIntersectionObserver from '../../lib/hooks/useIntersectionObserver'
import {COPY, HERO_VISUALS} from './Security.data'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from './utils/responsive'
import type Assets from './webgl-utils/assets'

export default function Security({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
  const [isMounted, setIsMounted] = useState<boolean>(false)
  const mainGridRef = useRef<HTMLDivElement | null>(null)

  const {footnoteStates, initFootnotes, onFootnoteClick, onFootnoteEnter, onFootnoteKeyDown} = useFootnotes()
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
      threshold: {mobile: 0.2, desktop: 0.4},
      isOnce: true,
    },
    !isSmallHeight && isDesktopView,
  )

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
                <Statistic.Heading className="Security-statisticHeading" size="4">
                  {statistic.heading}
                </Statistic.Heading>

                <Statistic.Description className="Security-statisticDescription">
                  {/* eslint-disable-next-line react/no-danger */}
                  <span dangerouslySetInnerHTML={{__html: statistic.description}} />
                  {statistic.footnote && (
                    <FootnoteToggle
                      isExpanded={!!footnoteStates[statistic.footnote.number]}
                      number={statistic.footnote.number}
                      onClick={onFootnoteClick}
                      onEnter={onFootnoteEnter}
                      onKeyDown={onFootnoteKeyDown}
                    />
                  )}
                </Statistic.Description>
              </Statistic>

              {statistic.footnote && (
                <Footnote {...statistic.footnote} isVisible={!!footnoteStates[statistic.footnote.number]} />
              )}
            </div>
          </Grid.Column>
        ))}
      </WrapperElement>
    )
  }, [footnoteStates, hasEmptyCell, isMainGridInView, onFootnoteClick, onFootnoteEnter, onFootnoteKeyDown])

  useEffect(() => {
    setIsMounted(true)
  }, [])

  useEffect(() => {
    if (!isMounted) return

    const footnoteNumbers = COPY.statistics
      .filter(statistic => statistic.footnote && Number.isFinite(statistic.footnote.number))
      .map(statistic => statistic.footnote!.number)

    initFootnotes(footnoteNumbers)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMounted])

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
                <div>
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
