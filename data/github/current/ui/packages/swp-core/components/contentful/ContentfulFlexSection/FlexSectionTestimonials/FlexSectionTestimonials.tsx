import {Box, Grid, Image} from '@primer/react-brand'
import {ContentfulTestimonials} from '../../ContentfulTestimonials/ContentfulTestimonials'
import type {PrimerTestimonials} from '../../../../schemas/contentful/contentTypes/primerTestimonials'
import styles from './FlexSectionTestimonials.module.css'
import {backgroundStylesMap} from './config'
import {clsx} from 'clsx'

type FlexSectionTestimonialsProps = {
  testimonials: PrimerTestimonials['fields']['testimonials']
  backgroundImageVariant?: 'Productivity' | 'Collaboration' | 'AI' | 'Security' | 'Enterprise' | undefined
  className?: string
}

export function FlexSectionTestimonials({
  testimonials,
  backgroundImageVariant,
  className,
}: FlexSectionTestimonialsProps) {
  // The default variant is 'minimal', so if the variant is not set, we should treat it as 'minimal'.
  const isMinimalVariant = !testimonials[0]?.fields?.variant || testimonials[0]?.fields?.variant === 'minimal'

  const set = !isMinimalVariant && backgroundImageVariant ? backgroundStylesMap[backgroundImageVariant] : undefined

  return set ? (
    <Grid>
      <Grid.Column>
        <Box
          className={clsx('position-relative', set.className)}
          marginBlockStart={{narrow: 'none', wide: set.marginBlockStart}}
          marginBlockEnd={{narrow: 'none', wide: set.marginBlockEnd}}
        >
          <Image
            src={set.left.image}
            alt=""
            className={clsx(styles.testimonialBackgroundImageShape, styles.left)}
            width={set.left.width}
            loading="lazy"
          />
          <Image
            src={set.right.image}
            alt=""
            className={clsx(styles.testimonialBackgroundImageShape, styles.right)}
            width={set.right.width}
            loading="lazy"
          />

          <ContentfulTestimonials className={className} testimonials={testimonials} />
        </Box>
      </Grid.Column>
    </Grid>
  ) : (
    <ContentfulTestimonials className={className} testimonials={testimonials} />
  )
}
