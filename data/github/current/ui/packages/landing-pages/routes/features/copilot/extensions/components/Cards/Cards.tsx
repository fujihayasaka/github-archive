import {Card as PrimerCard, Grid, BreakpointSize, useWindowSize} from '@primer/react-brand'
import type React from 'react'
import {useMemo, useRef} from 'react'

import type {CardData} from '../../Index.data'
import useIntersectionObserver from '../../../../../../lib/hooks/useIntersectionObserver'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../utils/responsive'

interface CardsProps {
  items: CardData[]
}

const defaultProps: Partial<CardsProps> = {}

const Cards: React.FC<CardsProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items} = initializedProps

  const wrapperRef = useRef<HTMLDivElement>(null)

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

  const {isIntersecting: isInView} = useIntersectionObserver(
    wrapperRef,
    {
      threshold: {mobile: 0.15, desktop: 0.4},
      isOnce: true,
    },
    !isSmallHeight && isDesktopView,
  )

  return (
    <div ref={wrapperRef}>
      <Grid className="lp-Grid">
        {items.map((card, index) => {
          const CardIcon = <card.icon />
          return (
            <Grid.Column
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`card_${index}`}
              className={`lp-GridColumn ${!isInView ? 'lp-GridColumn--hidden' : ''}`}
              span={{xsmall: 12, medium: 6, large: 4}}
              style={{'--staggerIndex': index}}
            >
              <PrimerCard className="lp-Card" ctaText={card.cta.label} href={card.cta.url}>
                <PrimerCard.Icon className="lp-Card-icon" icon={CardIcon} color="purple" />
                <PrimerCard.Heading size="6">{card.title}</PrimerCard.Heading>
                <PrimerCard.Description>{card.description}</PrimerCard.Description>
              </PrimerCard>
            </Grid.Column>
          )
        })}
      </Grid>
    </div>
  )
}

export default Cards
