import {Statistic, type AnimateProps} from '@primer/react-brand'
import type {PrimerComponentStatistic} from '../../../schemas/contentful/contentTypes/primerComponentStatistic'

export type ContentfulStatisticProps = {
  animate?: AnimateProps
  component: PrimerComponentStatistic
  className?: string
  headingElementSize?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  bgColor?: 'default' | 'subtle'
}

export function ContentfulStatistic({
  component,
  animate,
  className,
  headingElementSize = 'h3',
  bgColor,
}: ContentfulStatisticProps) {
  const {heading, size, variant, description, descriptionVariant} = component.fields

  return (
    <Statistic
      className={className}
      variant={variant}
      size={size}
      animate={animate}
      // The "boxed" variant of the statistic applies a background color, but when the page
      // background is "subtle," the statistic's background blends in, making it appear as
      // if it's not using the boxed variant. This explicitly sets the background color to
      // ensure the boxed variant stands out on both "default" and "subtle" backgrounds.
      style={{backgroundColor: bgColor && variant === 'boxed' ? `var(--brand-color-canvas-${bgColor})` : undefined}}
    >
      <Statistic.Heading as={headingElementSize}>{heading}</Statistic.Heading>
      <Statistic.Description variant={descriptionVariant}>{description}</Statistic.Description>
    </Statistic>
  )
}
