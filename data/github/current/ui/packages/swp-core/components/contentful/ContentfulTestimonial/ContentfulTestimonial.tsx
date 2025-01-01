import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import {FrostedGlassVFX, Testimonial, type TestimonialProps} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {PrimerComponentTestimonial} from '../../../schemas/contentful/contentTypes/primerComponentTestimonial'

export type ContentfulTestimonialContentProps = Pick<TestimonialProps, 'quoteMarkColor' | 'size' | 'variant'> & {
  component: PrimerComponentTestimonial
}

export type ContentfulTestimonialProps = Pick<TestimonialProps, 'quoteMarkColor' | 'size'> & {
  component: PrimerComponentTestimonial
}

export const ContentfulTestimonialContent = ({
  component,
  size,
  quoteMarkColor,
  variant,
}: ContentfulTestimonialContentProps) => {
  const fallbackAltText = component.fields.author?.fields.fullName ?? 'The testimonial author'
  const displayedAuthorImage = component.fields.displayedAuthorImage
  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')

  return (
    <Testimonial
      size={size ? size : component.fields.size}
      variant={variant}
      quoteMarkColor={quoteMarkColor || component.fields.quoteMarkColor}
    >
      <Testimonial.Quote>
        {
          documentToReactComponents(component.fields.quote, {
            renderMark: {
              /**
               * We use <em> to benefit from Primer Brand's special styling for <em> tags.
               */
              [MARKS.BOLD]: text => <em>{text}</em>,
            },
            renderNode: {
              /**
               * We don't need to wrap paragraphs in <p> tags.
               */
              [BLOCKS.PARAGRAPH]: (_, children) => children,
            },

            /* eslint-disable-next-line @typescript-eslint/no-explicit-any --
             *
             * We cast to any because types from @contentful/rich-text-react-renderer are too broad for
             * the Primer Brand's Testimonial.Quote component.
             */
          }) as any
        }
      </Testimonial.Quote>

      {component.fields.author && (
        <Testimonial.Name position={component.fields.author.fields.position}>
          {component.fields.author.fields.fullName}
        </Testimonial.Name>
      )}

      {displayedAuthorImage === 'logo' && component.fields.logo !== undefined ? (
        <Testimonial.Logo>
          <img
            src={
              optimizeImageEnabled
                ? `${component.fields.logo.fields.file.url}?fm=webp&w=120&q=90`
                : component.fields.logo.fields.file.url
            }
            alt={component.fields.logo.fields.description ?? ''}
            width={60}
          />
        </Testimonial.Logo>
      ) : displayedAuthorImage === 'avatar' && component.fields.author?.fields.photo !== undefined ? (
        <Testimonial.Avatar
          alt={component.fields.author.fields.photo.fields.description ?? fallbackAltText}
          src={
            optimizeImageEnabled
              ? `${component.fields.author.fields.photo.fields.file.url}?fm=webp&w=120&q=90`
              : component.fields.author.fields.photo.fields.file.url
          }
        />
      ) : /**
       * If neither logo nor author's photo exist or none is selected, we don't render anything.
       */
      null}
    </Testimonial>
  )
}

export function ContentfulTestimonial({component, size, quoteMarkColor}: ContentfulTestimonialProps) {
  return component.fields.variant === 'frosted-glass' ? (
    <FrostedGlassVFX>
      <ContentfulTestimonialContent
        component={component}
        size={size}
        quoteMarkColor={quoteMarkColor}
        variant="default"
      />
    </FrostedGlassVFX>
  ) : (
    <ContentfulTestimonialContent
      component={component}
      size={size}
      quoteMarkColor={quoteMarkColor}
      variant={component.fields.variant}
    />
  )
}
