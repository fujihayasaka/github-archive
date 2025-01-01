import {Grid} from '@primer/react-brand'

import type {PrimerTestimonials} from '../../../schemas/contentful/contentTypes/primerTestimonials'
import {ContentfulTestimonial} from '../ContentfulTestimonial/ContentfulTestimonial'

/**
 * Uses TypeScript discriminated union to ensure the component accepts either a `component`
 * or a `testimonials` prop, but not both. This increases the flexibility
 * of this component by supporting either a primerTestimonials entry or a
 * plain array of primerComponentTestimonial entries.
 */
export type ContentfulTestimonialsProps =
  | {
      component: PrimerTestimonials
      testimonials?: never
      className?: string
    }
  | {
      testimonials: PrimerTestimonials['fields']['testimonials']
      component?: never
      className?: string
    }

export function ContentfulTestimonials({component, testimonials, className}: ContentfulTestimonialsProps) {
  const collection = component !== undefined ? component.fields.testimonials : testimonials

  const isSingleTestimonial = collection.length === 1

  return (
    <Grid className={className}>
      {collection.map(testimonial => (
        <Grid.Column
          start={isSingleTestimonial ? {medium: 2} : undefined}
          span={{medium: isSingleTestimonial ? 10 : 6}}
          key={testimonial.sys.id}
        >
          <ContentfulTestimonial component={testimonial} size={isSingleTestimonial ? 'large' : 'small'} />
        </Grid.Column>
      ))}
    </Grid>
  )
}
