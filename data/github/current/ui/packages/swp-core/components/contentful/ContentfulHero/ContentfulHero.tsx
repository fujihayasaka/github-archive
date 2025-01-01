import {Box, Hero} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {PrimerComponentHero} from '../../../schemas/contentful/contentTypes/primerComponentHero'
import {ContentfulAppStoreButtonGroup} from '../ContentfulAppStoreButtonGroup/ContentfulAppStoreButtonGroup'
import {getPrimerIcon} from '../../../lib/utils/icons'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'
import styles from './ContentfulHero.module.css'
import {HeroVideo} from './HeroVideo/HeroVideo'

export type ContentfulHeroProps = {
  component: PrimerComponentHero

  'data-hpc'?: boolean
}

export function ContentfulHero({component, ...props}: ContentfulHeroProps) {
  const {
    align,
    callToActionPrimary,
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
  } = component.fields

  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')
  const videoCoverImageEnabled = isFeatureEnabled('contentful_lp_hero_video_cover_image')

  const isHeroImage = image && (!videoSrc || !videoCoverImageEnabled)

  const hasTrailingComponent = trailingComponent !== undefined && trailingComponent.length > 0

  const Octicon = typeof label !== 'string' && getPrimerIcon(label?.fields.icon)

  return (
    <Box className={styles.contentfulHeroContainer}>
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
        {isHeroImage &&
          (optimizeImageEnabled ? (
            <Hero.Image
              as="picture"
              position={imagePosition === 'Inline' ? 'inline-end' : 'block-end'}
              src={`${image.fields.file.url}?fm=webp`}
              sources={getImageSources(image.fields.file.url, {maxWidth: MAX_CONTENT_WIDTH})}
              alt={image.fields.description || ''}
            />
          ) : (
            <Hero.Image
              position={imagePosition === 'Inline' ? 'inline-end' : 'block-end'}
              src={image.fields.file.url}
              alt={image.fields.description || ''}
            />
          ))}
      </Hero>
      {videoSrc !== undefined && !isHeroImage && (
        <HeroVideo videoSrc={videoSrc} heading={heading} image={image} optimizeImageEnabled={optimizeImageEnabled} />
      )}
    </Box>
  )
}
