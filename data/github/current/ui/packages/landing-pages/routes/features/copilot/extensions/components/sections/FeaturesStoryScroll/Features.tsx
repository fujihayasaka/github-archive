import {Image, SectionIntro, Heading, Link, Text, useWindowSize} from '@primer/react-brand'
import {useEffect, useMemo, useRef} from 'react'

import {COPY} from '../../../Index.data'
import {Spacer} from '../../../../../components/Spacer'
import {wait} from '../../../utils/time'
import useActiveItemDetection from './hooks/useActiveItemDetection'
import useIntersectionObserver from '../../../../../../../lib/hooks/useIntersectionObserver'

interface FeaturesProps {}

const defaultProps: Partial<FeaturesProps> = {}

const Features: React.FC<FeaturesProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const containerRef = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const sectionIntroRef = useRef<HTMLDivElement>(null)

  const windowSize = useWindowSize()

  const {currentItemIndex, previousItemIndex} = useActiveItemDetection({itemContainerRef: contentRef, threshold: 0.8})
  const {isIntersecting: isSectionIntroInView} = useIntersectionObserver(sectionIntroRef, {
    threshold: 1,
    isOnce: true,
  })

  useEffect(() => {
    const proceed = async () => {
      const image = containerRef.current?.querySelector('.lp-Features-visuals-image')
      const lastItem = containerRef.current?.querySelector('.lp-Features-content-item:last-child > div')
      if (!image || !lastItem || !containerRef.current) return

      const {height: visualHeight} = image.getBoundingClientRect()
      if (!visualHeight) {
        await wait(100)
        proceed()
        return
      }

      const {height: lastItemHeight} = lastItem.getBoundingClientRect()

      containerRef.current.style.setProperty('--visualHeight', `${visualHeight}px`)
      containerRef.current.style.setProperty('--stickyBottomMargin', `${lastItemHeight}px`)
    }

    proceed()
  }, [windowSize])

  const itemsDOM = useMemo(
    () => (
      <div ref={containerRef} className="lp-Features-container">
        <div ref={contentRef} className="lp-Features-content">
          {COPY.features.items.map((item, index) => (
            <div
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`content_${index}`}
              className={`lp-Features-content-item ${
                index === currentItemIndex ? 'lp-Features-content-item--current' : ''
              }`}
            >
              <div>
                <Heading as="h3" size="5" className="lp-Features-content-itemTitle">
                  {item.title}
                </Heading>
                <Text className="lp-Features-content-itemDescription">{item.description}</Text>
                {item.link && (
                  <Link className="lp-Features-content-itemLink" variant="accent" href={item.link.url}>
                    {item.link.label}
                  </Link>
                )}
              </div>
            </div>
          ))}
        </div>
        <div className="lp-Features-visuals">
          {COPY.features.items.map((item, index) => (
            <Image
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`visual_${index}`}
              src={item.image.url}
              alt={item.image.alt}
              className={`lp-Features-visuals-image ${
                index === currentItemIndex ? 'lp-Features-visuals-image--current' : ''
              } ${index === previousItemIndex ? 'lp-Features-visuals-image--previous' : ''}`}
            />
          ))}
        </div>
      </div>
    ),
    [currentItemIndex, previousItemIndex],
  )

  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="96px" size768="128px" />

        <div ref={sectionIntroRef}>
          <SectionIntro
            className={`fp-SectionIntro lp-SectionIntro ${!isSectionIntroInView ? 'lp-SectionIntro--hidden' : ''}`}
            fullWidth
          >
            <SectionIntro.Label className="lp-SectionIntro-label">{COPY.features.label}</SectionIntro.Label>
            <SectionIntro.Heading
              size="3"
              // eslint-disable-next-line react/forbid-component-props
              dangerouslySetInnerHTML={{__html: COPY.features.title}}
            />
          </SectionIntro>
        </div>

        <Spacer size="80px" size768="112px" />

        {itemsDOM}
      </div>
    </section>
  )
}

export default Features
