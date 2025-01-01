import {Fragment, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {BreakpointSize, Button, Grid, Image, Link, Text, useWindowSize} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {Spacer} from './_shared'
import SectionIntro from './components/SectionIntro/SectionIntro'
import {COPY, CUSTOMER_STORIES, StoryCategory} from './CustomerStories.data'
import Toggle from './components/Toggle/Toggle'
import {wait} from './utils/time'
import type Assets from './webgl-utils/assets'
import {ChevronRightIcon} from '@primer/octicons-react'

export default function CustomerStories({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
  const [currentCategory, setCurrentCategory] = useState<StoryCategory>(StoryCategory.Industry)
  const [visibleCategory, setVisibleCategory] = useState<StoryCategory>(currentCategory)
  const gridWrapperRef = useRef<HTMLDivElement>(null)
  const windowSize = useWindowSize()

  const visibleCategoryIndex = useMemo(() => Number(visibleCategory), [visibleCategory])
  const [toggleWrapperTopPadding, setToggleWrapperSpacing] = useState(0)

  const currentStories = useMemo(
    () =>
      Object.values(CUSTOMER_STORIES[currentCategory])
        .map(subCategories => {
          return Object.values(subCategories).sort((a, b) => Number(a.subCategory) - Number(b.subCategory))
        })
        .flat(),
    [currentCategory],
  )

  const onCategoryChange = useCallback(
    async (category: StoryCategory) => {
      if (!gridWrapperRef.current || category === currentCategory) return

      const grid = gridWrapperRef.current.querySelector('.lp-CustomerStories-grid')
      if (!grid) return

      setVisibleCategory(category)
      grid.classList.add('lp-CustomerStories-grid--hidden')
      await wait(250)

      setCurrentCategory(category)
      await wait(250)

      grid.classList.remove('lp-CustomerStories-grid--hidden')
    },
    [currentCategory],
  )

  // toggleWrapper spacing
  // This adds extra padding in case the global and/or flash banner is shown
  useEffect(() => {
    const updateToggleWrapperSpacing = () => {
      if (windowSize?.width !== undefined && windowSize?.width <= 1011) {
        let extraHeaderHeight = document.querySelector('.global-banner')?.clientHeight || 0
        extraHeaderHeight += document.querySelector('.js-stale-session-flash')?.clientHeight || 0

        setToggleWrapperSpacing(extraHeaderHeight)
      }
    }

    updateToggleWrapperSpacing()

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', updateToggleWrapperSpacing)

    return () => {
      window.removeEventListener('resize', updateToggleWrapperSpacing)
    }
  }, [windowSize.width])

  return (
    <section id="customer-stories" className="lp-Section">
      <div className="lp-CustomerStories-stickyContainer">
        <div className="lp-SectionBlock lp-SectionBlock--noBorder">
          <div className="lp-SectionBlock-content">
            <SectionIntro
              mascot="ducky"
              title={COPY.intro.title}
              assetsRef={assetsRef}
              bottomSpacerSize="small"
              isWebGLMascotOnly
            />
          </div>
        </div>

        <div
          className="lp-CustomerStories-toggleWrapper"
          style={{paddingTop: toggleWrapperTopPadding > 0 ? `${toggleWrapperTopPadding}px` : ''}}
        >
          <Toggle
            currentIndex={visibleCategoryIndex}
            items={Object.entries(COPY.content.categories).map(([category, label]) => ({label, value: category}))}
            ariaLabel={COPY.content.aria.toggle}
            onToggle={(value: string) => onCategoryChange(Number(value) as StoryCategory)}
            hasBackground
          />
        </div>

        <Spacer size="32px" size1012="56px" />

        <hr className="lp-CustomerStories-sectionBlockDivider" />

        <div ref={gridWrapperRef} className="lp-SectionBlock">
          <div className="lp-SectionBlock-content lp-SectionBlock-content--lines lp-SectionBlock-content--narrow">
            <Grid className="lp-CustomerStories-grid lp-CustomerStories-grid--customerStories">
              {currentStories.map((story, index) => (
                <Grid.Column
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  key={`story_${index}`}
                  className="lp-CustomerStories-gridColumn"
                  span={{xsmall: 12, medium: 12, large: 4}}
                  style={
                    {'--backgroundUrl': `url(${story.backgroundUrl})`, '--staggerIndex': index} as React.CSSProperties
                  }
                >
                  <Button
                    className="lp-CustomerStories-button"
                    as="a"
                    href={story.url}
                    hasArrow={false}
                    {...getAnalyticsEvent({
                      action: COPY.content.readMore,
                      tag: 'link',
                      context: COPY.content.subCategories[story.subCategory],
                      location: COPY.analyticsId,
                    })}
                  >
                    <div className="lp-CustomerStories-logoContainer">
                      <Image
                        className="lp-CustomerStories-logo"
                        src={story.logo.url}
                        alt={story.logo.alt}
                        style={{height: story.logo.height}}
                        loading="lazy"
                      />
                    </div>

                    <div className="lp-CustomerStories-content">
                      <Text className="lp-CustomerStories-label" variant="muted" weight="semibold">
                        {COPY.content.subCategories[story.subCategory]}
                      </Text>
                      <Text className="lp-CustomerStories-description" as="p">
                        {story.description}
                      </Text>

                      <div className="lp-CustomerStories-storyLink">
                        <Text as="span">
                          {COPY.content.readMore}
                          <ChevronRightIcon />
                        </Text>
                      </div>
                    </div>
                  </Button>
                </Grid.Column>
              ))}

              {/* Add empty column to fill the grid if needed */}
              {[BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
                windowSize.currentBreakpointSize!,
              ) &&
                currentStories.length % 3 !== 0 && (
                  <Grid.Column
                    className="lp-CustomerStories-gridColumn lp-CustomerStories-gridColumn--dummy"
                    span={{xsmall: 12, medium: 6, large: 4}}
                  />
                )}
            </Grid>
          </div>
        </div>
      </div>

      <div className="lp-SectionBlock lp-SectionBlock--noBorder">
        <div className="lp-SectionBlock-content">
          <Spacer size="0px" size1012="48px" />

          {/* Links */}
          <div className="lp-CustomerStories-links">
            {COPY.links.map((link, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <Fragment key={`link_${index}`}>
                <div>
                  <Link
                    variant="accent"
                    className="lp-CustomerStories-link"
                    href={link.url}
                    {...getAnalyticsEvent({
                      action: link.label,
                      tag: 'link',
                      context: 'footer',
                      location: COPY.analyticsId,
                    })}
                  >
                    <Text weight="normal" size="300">
                      {link.label}
                    </Text>
                  </Link>
                </div>

                {index < COPY.links.length - 1 && <hr className="lp-CustomerStories-divider" />}
              </Fragment>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
