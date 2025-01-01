import {Box, type BoxSpacingValues, Hero} from '@primer/react-brand'

import type {PrimerComponentHero} from '../../../schemas/contentful/contentTypes/primerComponentHero'
import {ContentfulAppStoreButtonGroup} from '../ContentfulAppStoreButtonGroup/ContentfulAppStoreButtonGroup'
import {getPrimerIcon} from '../../../lib/utils/icons'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'
import styles from './ContentfulHero.module.css'
import {HeroVideo} from './HeroVideo/HeroVideo'
import {ContentfulAnimatedVideo} from '../ContentfulAnimatedVideo/ContentfulAnimatedVideo'

type SpacingValues = (typeof BoxSpacingValues)[number]
type ResponsiveSpacingMap = {
  narrow?: SpacingValues
  regular?: SpacingValues
  wide?: SpacingValues
}

export type ContentfulHeroProps = {
  component: PrimerComponentHero
  paddingBlockEnd?: SpacingValues | ResponsiveSpacingMap
  'data-hpc'?: boolean
}

export function ContentfulHero({component, paddingBlockEnd, ...props}: ContentfulHeroProps) {
  const {
    align,
    callToActionPrimary,
    callToActionPrimaryVariant,
    callToActionSecondary,
    description,
    descriptionVariant,
    heading,
    headingSize,
    image,
    imagePosition,
    label,
    labelColor,
    trailingComponent,
    videoSrc,
    animatedVideo,
  } = component.fields

  const isHeroImage = image && !videoSrc

  const hasTrailingComponent = trailingComponent !== undefined && trailingComponent.length > 0

  const Octicon = typeof label !== 'string' && getPrimerIcon(label?.fields.icon)

  return (
    <Box className={styles.contentfulHeroContainer} paddingBlockEnd={paddingBlockEnd || {narrow: 96, regular: 128}}>
      <Hero
        data-hpc={props['data-hpc']}
        align={align}
        trailingComponent={
          hasTrailingComponent
            ? () => (
                <ContentfulAppStoreButtonGroup
                  components={trailingComponent}
                  analyticsLabel="hero"
                  analyticsLocation="hero"
                />
              )
            : undefined
        }
        className="pb-0"
      >
        {label &&
          (typeof label === 'string' ? (
            <Hero.Label {...(labelColor ? {color: labelColor} : {})}>{label}</Hero.Label>
          ) : (
            <Hero.Label
              color={label.fields.color}
              size={label.fields.size}
              {...(Octicon ? {leadingVisual: <Octicon />} : {})}
            >
              {label.fields.text}
            </Hero.Label>
          ))}

        <Hero.Heading size={headingSize}>{heading}</Hero.Heading>

        {description && <Hero.Description variant={descriptionVariant}>{description}</Hero.Description>}

        {!hasTrailingComponent && callToActionPrimary !== undefined && (
          <Hero.PrimaryAction
            href={callToActionPrimary.fields.href}
            variant={callToActionPrimaryVariant || 'primary'}
            data-ref={`hero-primary-action-${callToActionPrimary.sys.id}`}
            {...getAnalyticsEvent(
              {
                action: callToActionPrimary.fields.text,
                tag: 'button',
                location: 'hero',
                context: 'CTAs',
              },
              {context: false},
            )}
          >
            {callToActionPrimary.fields.text}
          </Hero.PrimaryAction>
        )}

        {!hasTrailingComponent && callToActionSecondary !== undefined && (
          <Hero.SecondaryAction
            href={callToActionSecondary.fields.href}
            {...getAnalyticsEvent(
              {
                action: callToActionSecondary.fields.text,
                tag: 'button',
                location: 'hero',
                context: 'CTAs',
              },
              {context: false},
            )}
          >
            {callToActionSecondary.fields.text}
          </Hero.SecondaryAction>
        )}
        {isHeroImage && (
          <Hero.Image
            as="picture"
            position={imagePosition === 'Inline' ? 'inline-end' : 'block-end'}
            src={`${image.fields.file.url}?fm=webp`}
            sources={getImageSources(image.fields.file.url, {maxWidth: MAX_CONTENT_WIDTH})}
            alt={image.fields.description || ''}
          />
        )}
      </Hero>
      {videoSrc !== undefined && !isHeroImage && <HeroVideo videoSrc={videoSrc} heading={heading} image={image} />}
      {!videoSrc && !image && animatedVideo && (
        <Box paddingBlockStart={80}>
          <ContentfulAnimatedVideo component={animatedVideo} analyticsLocation="hero" />
        </Box>
      )}
    </Box>
  )
}
