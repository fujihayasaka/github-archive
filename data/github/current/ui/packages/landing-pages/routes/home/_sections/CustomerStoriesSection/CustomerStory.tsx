import {ChevronRightIcon} from '@primer/octicons-react'
import {Button, Grid, Image, Text} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import type {GenericContent} from '../../../../brand/lib/types/contentful'

type Props = {
  story: GenericContent
  analyticsId: string
  index: number
}

export function CustomerStory(props: Props) {
  const {story, analyticsId, index} = props

  const {heading, label, links, media} = story.fields

  const firstLink = links?.at(0)

  const logo = media?.find(item => item.fields.id === 'logo')
  const backgroundImage = media?.find(item => item.fields.id === 'backgroundImage')

  return (
    <Grid.Column
      key={story.sys.id}
      className="lp-CustomerStories-gridColumn"
      span={{xsmall: 12, medium: 12, large: 4}}
      style={{'--staggerIndex': index}}
    >
      {firstLink ? (
        <Button
          className="lp-CustomerStories-button"
          as="a"
          href={firstLink.fields.href}
          hasArrow={false}
          {...getAnalyticsEvent({
            action: firstLink.fields.text,
            tag: 'link',
            context: (story.fields.label && story.fields.label.fields.text) || '',
            location: analyticsId,
          })}
        >
          {backgroundImage ? (
            <div className="lp-CustomerStories-backgroundContainer">
              <Image src={backgroundImage.fields.asset.fields.file.url} alt="" loading="lazy" />
            </div>
          ) : null}

          <div className="lp-CustomerStories-container">
            {logo ? (
              <div className="lp-CustomerStories-logoContainer">
                <Image
                  className="lp-CustomerStories-logo"
                  src={logo.fields.asset.fields.file.url}
                  alt={logo.fields.description || ''}
                  style={{height: logo.fields.height || logo.fields.asset.fields.file.details?.image?.height}}
                  loading="lazy"
                />
              </div>
            ) : null}

            <div className="lp-CustomerStories-content">
              {label ? (
                <Text className="lp-CustomerStories-label" variant="muted" weight="semibold">
                  {label.fields.text}
                </Text>
              ) : null}

              {heading ? (
                <Text className="lp-CustomerStories-description" as="p">
                  {heading}
                </Text>
              ) : null}

              <div className="lp-CustomerStories-storyLink">
                <Text as="span">
                  {firstLink.fields.text}
                  <ChevronRightIcon />
                </Text>
              </div>
            </div>
          </div>
        </Button>
      ) : null}
    </Grid.Column>
  )
}
