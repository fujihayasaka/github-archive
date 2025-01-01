import {Fragment, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {BreakpointSize, Grid, Link, Text, useWindowSize} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import {documentToPlainTextString} from '@contentful/rich-text-plain-text-renderer'
import type {GenericSectionWithIds, GenericGroup, GenericContent} from '../../../../brand/lib/types/contentful'

import SectionIntro from '../../components/SectionIntro/SectionIntro'
import Toggle from '../../components/Toggle/Toggle'

import {Spacer} from '../../_shared'
import {wait} from '../../utils/time'

import type Assets from '../../webgl-utils/assets'

import {CustomerStory} from './CustomerStory'

const ANALYTICS_ID = 'customer_stories'

type Props = {
  contentfulContent: GenericSectionWithIds
  assetsRef: React.RefObject<Assets>
}

export function CustomerStoriesSection(props: Props) {
  const {contentfulContent, assetsRef} = props

  const {customerStoriesSectionContent, customerStoriesSectionStories} = contentfulContent.ids as {
    customerStoriesSectionContent: GenericContent
    customerStoriesSectionStories: GenericGroup
  }

  const [currentCategory, setCurrentCategory] = useState<number>(0)
  const [visibleCategory, setVisibleCategory] = useState<number>(currentCategory)
  const gridWrapperRef = useRef<HTMLDivElement>(null)
  const windowSize = useWindowSize()

  const visibleCategoryIndex = useMemo(() => Number(visibleCategory), [visibleCategory])
  const [toggleWrapperTopPadding, setToggleWrapperSpacing] = useState(0)

  const onCategoryChange = useCallback(
    async (category: number) => {
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

  const storyCategories =
    customerStoriesSectionStories && customerStoriesSectionStories.fields.content
      ? (customerStoriesSectionStories.fields.content as GenericContent[])
      : undefined

  const currentCustomerStoriesCategory = storyCategories
    ? (storyCategories[currentCategory] as GenericContent)
    : undefined

  return (
    <section id="customer-stories" className="lp-Section">
      <div className="lp-CustomerStories-stickyContainer">
        {customerStoriesSectionContent ? (
          <div className="lp-SectionBlock lp-SectionBlock--noBorder">
            <div className="lp-SectionBlock-content">
              <SectionIntro
                mascot="ducky"
                title={`${customerStoriesSectionContent.fields.heading} <span>${
                  customerStoriesSectionContent.fields.subheading
                    ? documentToPlainTextString(customerStoriesSectionContent.fields.subheading)
                    : ''
                }</span>`}
                assetsRef={assetsRef}
                bottomSpacerSize="small"
                isWebGLMascotOnly
              />
            </div>
          </div>
        ) : null}

        {storyCategories ? (
          <div
            className="lp-CustomerStories-toggleWrapper"
            style={{
              paddingTop:
                toggleWrapperTopPadding && toggleWrapperTopPadding > 0 ? `${toggleWrapperTopPadding}px` : undefined,
            }}
          >
            <Toggle
              currentIndex={visibleCategoryIndex}
              items={storyCategories.map((category, index) => ({
                label: category.fields.heading || '',
                value: `${index}`,
              }))}
              onToggle={(value: string) => onCategoryChange(Number(value))}
              hasBackground
            />
          </div>
        ) : null}

        <Spacer size="32px" size1012="56px" />

        <hr className="lp-CustomerStories-sectionBlockDivider" />

        <div ref={gridWrapperRef} className="lp-SectionBlock">
          <div className="lp-SectionBlock-content lp-SectionBlock-content--lines lp-SectionBlock-content--narrow">
            <Grid className="lp-CustomerStories-grid lp-CustomerStories-grid--customerStories">
              {currentCustomerStoriesCategory && currentCustomerStoriesCategory.fields.content ? (
                <>
                  {(currentCustomerStoriesCategory.fields.content as GenericContent[]).map((story, index) => (
                    <CustomerStory key={story.sys.id} story={story} analyticsId={ANALYTICS_ID} index={index} />
                  ))}

                  {/* Add empty column to fill the grid if needed */}
                  {[BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
                    windowSize.currentBreakpointSize!,
                  ) &&
                    currentCustomerStoriesCategory.fields.content.length % 3 !== 0 && (
                      <Grid.Column
                        className="lp-CustomerStories-gridColumn lp-CustomerStories-gridColumn--dummy"
                        span={{xsmall: 12, medium: 6, large: 4}}
                      />
                    )}
                </>
              ) : null}
            </Grid>
          </div>
        </div>
      </div>

      <div className="lp-SectionBlock lp-SectionBlock--noBorder">
        <div className="lp-SectionBlock-content">
          <Spacer size="0px" size1012="48px" />

          {customerStoriesSectionContent && customerStoriesSectionContent.fields.links ? (
            <div className="lp-CustomerStories-links">
              {customerStoriesSectionContent.fields.links.map((link, index) => (
                <Fragment key={link.sys.id}>
                  <div>
                    <Link
                      variant="accent"
                      className="lp-CustomerStories-link"
                      href={link.fields.href || ''}
                      {...getAnalyticsEvent({
                        action: link.fields.text,
                        tag: 'link',
                        context: 'footer',
                        location: ANALYTICS_ID,
                      })}
                    >
                      <Text weight="normal" size="300">
                        {link.fields.text}
                      </Text>
                    </Link>
                  </div>

                  {index < (customerStoriesSectionContent.fields.links?.length ?? 0) - 1 && (
                    <hr className="lp-CustomerStories-divider" />
                  )}
                </Fragment>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </section>
  )
}
