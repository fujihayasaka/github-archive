import {Box, Grid, Card, type GridColumnIndex} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import styles from './CategoryCards.module.css'
import {formatPublishedDate} from '../../lib/utils'
import type {CategoryCardsProps} from '../../lib/types/categoryCard'

export function CategoryCards({cards, hasBorder, fullWidth = false, animate, className, spanOpts}: CategoryCardsProps) {
  const desktop = cards.length > 2 ? 4 : 6

  const span: {[key: string]: GridColumnIndex} = {
    xsmall: 12,
    small: 12,
    medium: 6,
    large: desktop,
    xlarge: desktop,
    xxlarge: desktop,
    ...spanOpts,
  }

  return (
    <Grid className={className}>
      {cards.map(({heading, href, publishedDate, ctaText, className: cardClassName}, index) => (
        <Grid.Column span={span} key={heading}>
          <Box
            animate={animate}
            className={`${styles.cardWrapper} height-full`}
            style={{'--custom-delay': `${(index % 6) * 50}ms`} as React.CSSProperties}
          >
            <Card
              data-ref={`card-action-${heading}`}
              href={href}
              ctaText={ctaText}
              className={cardClassName}
              hasBorder={hasBorder}
              fullWidth={fullWidth}
              {...getAnalyticsEvent({
                action: ctaText,
                tag: 'card',
                context: heading,
              })}
            >
              <Card.Heading as="h2">{heading}</Card.Heading>
              <Card.Description>
                <time>{formatPublishedDate(publishedDate)}</time>
              </Card.Description>
            </Card>
          </Box>
        </Grid.Column>
      ))}
    </Grid>
  )
}
