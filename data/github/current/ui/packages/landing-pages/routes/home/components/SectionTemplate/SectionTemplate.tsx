import {Grid, Heading, Image, Link, Pillar, Testimonial, Text} from '@primer/react-brand'
import {useCallback, useEffect, useRef, useState} from 'react'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import Accordion, {type AccordionProps} from '../Accordion/Accordion'
import SectionHero, {type SectionHeroProps} from '../SectionHero/SectionHero'
import SectionIntro, {type SectionIntroProps} from '../SectionIntro/SectionIntro'
import FootnoteLink from '../FootnoteLink/FootnoteLink'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'

export interface Customer {
  logo: {
    url: string
    alt: string
    height: number
  }
  description: string
  link: {
    url: string
    label: string
  }
}

interface SectionTemplateProps {
  intro: SectionIntroProps
  hero: SectionHeroProps
  customers?: Customer[]
  testimonial?: {
    quote: string
    name: string
    position: string
  }
  content: {
    title: string
    description: string
    footnote?: string
    link: {
      url: string
      label: string
    }
  }
  accordion: {
    items: AccordionProps['items']
  }
  analyticsId?: string
}

const SectionTemplate: React.FC<SectionTemplateProps> = ({
  analyticsId,
  intro,
  hero,
  content,
  customers,
  testimonial,
  accordion,
}) => {
  const [currentAccordionIndex, setCurrentAccordionIndex] = useState<number>(0)
  const [lastAccordionIndex, setLastAccordionIndex] = useState<number>(-1)
  const currentAccordionIndexRef = useRef<number>(currentAccordionIndex)
  const mainGridRef = useRef<HTMLDivElement | null>(null)

  const {isIntersecting: isMainGridInView} = useIntersectionObserver(mainGridRef, {threshold: 0.33, isOnce: true})

  const updateAccordionIndex = useCallback(
    (index: number) => {
      setLastAccordionIndex(currentAccordionIndex)
      setCurrentAccordionIndex(index)
    },
    [currentAccordionIndex],
  )

  useEffect(() => {
    currentAccordionIndexRef.current = currentAccordionIndex
  }, [currentAccordionIndex])

  return (
    <div className="lp-SectionTemplate">
      <div className="lp-SectionBlock">
        <div className="lp-SectionBlock-content">
          <SectionIntro {...intro} />
          <SectionHero {...hero} analyticsId={analyticsId} />
        </div>
      </div>

      <div className="lp-SectionBlock">
        <div ref={mainGridRef} className="lp-SectionBlock-content lp-SectionBlock-content--lines">
          <Grid className={`lp-SectionTemplate-grid ${!isMainGridInView ? 'lp-SectionTemplate-grid--hidden' : ''}`}>
            <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: testimonial ? 6 : 7}}>
              <div className="lp-SectionTemplate-content">
                <Heading as="h3" size="6" weight="semibold" className="lp-SectionTemplate-content-title">
                  {content.title}

                  {content.footnote && <FootnoteLink number={content.footnote} />}

                  <span>{content.description}</span>
                </Heading>

                <div>
                  <Link
                    href={content.link.url}
                    variant="accent"
                    className="lp-SectionTemplate-content-link"
                    {...getAnalyticsEvent({
                      action: content.link.label,
                      tag: 'link',
                      context: 'content',
                      location: analyticsId,
                    })}
                  >
                    <Text weight="normal" size="300">
                      {content.link.label}
                    </Text>
                  </Link>
                </div>
              </div>
            </Grid.Column>

            <Grid.Column className="lp-SectionTemplate-grid-column" span={{xsmall: 12, medium: testimonial ? 6 : 5}}>
              {testimonial && (
                <div className="lp-SectionTemplate-testimonial">
                  <Testimonial quoteMarkColor="green">
                    <Testimonial.Quote>{testimonial.quote}</Testimonial.Quote>

                    <Testimonial.Name position={testimonial.position}>{testimonial.name}</Testimonial.Name>
                  </Testimonial>
                </div>
              )}

              {customers &&
                customers.map((customer, index) => (
                  <div
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    key={`customer_${index}`}
                    className="lp-SectionTemplate-customer"
                  >
                    <Pillar>
                      <Pillar.Icon
                        className="lp-SectionTemplate-customer-logo"
                        icon={
                          <Image
                            src={customer.logo.url}
                            alt={customer.logo.alt}
                            height={customer.logo.height}
                            loading="lazy"
                          />
                        }
                      />

                      <Pillar.Description className="lp-SectionTemplate-customer-description">
                        <Text size="300">{customer.description}</Text>
                      </Pillar.Description>

                      <Pillar.Link
                        className="lp-SectionTemplate-customer-link"
                        href={customer.link.url}
                        {...getAnalyticsEvent({
                          action: customer.link.label,
                          tag: 'link',
                          context: 'customers',
                          location: analyticsId,
                        })}
                      >
                        <Text weight="normal" size="300">
                          {customer.link.label}
                        </Text>
                      </Pillar.Link>
                    </Pillar>
                  </div>
                ))}
            </Grid.Column>
          </Grid>
        </div>
      </div>

      <div className="lp-SectionBlock">
        <div className="lp-SectionBlock-content">
          <Grid className="lp-SectionTemplate-grid">
            <Grid.Column
              className="lp-SectionTemplate-grid-column lp-SectionTemplate-grid-column--noDesktopBorder lp-SectionTemplate-accordionVisual"
              span={{xsmall: 12, medium: 6}}
            >
              {accordion.items.map((item, index) => (
                <Image
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  key={`accordion_${index}`}
                  src={item.visual.url}
                  // The alt text is set in the Accordion component
                  alt=""
                  loading="lazy"
                  className={`
                    ${currentAccordionIndex === index ? 'lp-SectionTemplate-accordionVisual-image--current' : ''}
                    ${lastAccordionIndex === index ? 'lp-SectionTemplate-accordionVisual-image--last' : ''}
                  `}
                />
              ))}
            </Grid.Column>

            <Grid.Column
              className="lp-SectionTemplate-grid-column lp-SectionTemplate-accordionWrapper"
              span={{xsmall: 12, medium: 6}}
            >
              <Accordion
                items={accordion.items}
                currentIndex={currentAccordionIndex}
                onChange={updateAccordionIndex}
                analyticsId={analyticsId}
              />
            </Grid.Column>
          </Grid>
        </div>
      </div>
    </div>
  )
}

export default SectionTemplate
