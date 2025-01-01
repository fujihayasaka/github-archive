import {useCallback, useEffect, useRef, useState} from 'react'

import {Grid, Image} from '@primer/react-brand'

import Accordion, {type AccordionItem} from '../../components/Accordion/Accordion'

type Props = {
  items: AccordionItem[]
  analyticsId?: string
}

export function RiverAccordion(props: Props) {
  const {items, analyticsId} = props

  const [currentAccordionIndex, setCurrentAccordionIndex] = useState<number>(0)
  const [lastAccordionIndex, setLastAccordionIndex] = useState<number>(-1)

  const currentAccordionIndexRef = useRef<number>(currentAccordionIndex)

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
    <div className="lp-SectionBlock">
      <div className="lp-SectionBlock-content">
        <Grid className="lp-SectionTemplate-grid">
          <Grid.Column
            className="lp-SectionTemplate-grid-column lp-SectionTemplate-grid-column--noDesktopBorder lp-SectionTemplate-accordionVisual"
            span={{xsmall: 12, medium: 6}}
          >
            {items.map((item, index) => (
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
              items={items}
              currentIndex={currentAccordionIndex}
              onChange={updateAccordionIndex}
              analyticsId={analyticsId}
            />
          </Grid.Column>
        </Grid>
      </div>
    </div>
  )
}
