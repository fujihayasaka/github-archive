import {useState} from 'react'
import {Box, Image, Text} from '@primer/react-brand'
import {MarkGithubIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './HeroVideo.module.css'
import type {Asset} from '../../../../schemas/contentful/contentTypes/asset'
import {getImageSources, MAX_CONTENT_WIDTH} from '../../../../lib/utils/images'
import {PlayIcon} from './PlayIcon'

type HeroVideoProps = {
  videoSrc: string
  heading: string
  image?: Asset
  optimizeImageEnabled?: boolean
}

export function HeroVideo({videoSrc, heading, image, optimizeImageEnabled}: HeroVideoProps) {
  const [isPlaying, setIsPlaying] = useState(false)

  return !image || isPlaying ? (
    <Box className={clsx('position-relative width-full overflow-hidden', styles.contentContainer)}>
      <iframe
        role="application"
        className="border-0 width-full height-full position-absolute top-0 left-0"
        src={`${videoSrc}${image ? '?autoplay=1' : ''}`}
        title={heading}
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        // eslint-disable-next-line @eslint-react/dom/no-unsafe-iframe-sandbox
        sandbox="allow-scripts allow-same-origin"
        allowFullScreen
      />
    </Box>
  ) : (
    <Box className={clsx('position-relative width-full', styles.contentContainer)}>
      {optimizeImageEnabled ? (
        <Image
          as="picture"
          src={`${image.fields.file.url}?fm=webp`}
          sources={getImageSources(image.fields.file.url, {maxWidth: MAX_CONTENT_WIDTH})}
          alt={image.fields.description || ''}
          className={clsx('d-block', styles.posterImage)}
          loading="lazy"
          style={{display: 'block'}}
        />
      ) : (
        <Image
          src={image.fields.file.url}
          alt={image.fields.description || ''}
          className={clsx('d-block', styles.posterImage)}
          loading="lazy"
        />
      )}
      <Box
        padding={{narrow: 12, regular: 16}}
        className={clsx('position-absolute top-0 left-0 width-full', styles.posterImageTitleContainer)}
      >
        <MarkGithubIcon size={32} className={styles.posterBrandIcon} />
        {image.fields.description && (
          <Text size="200" weight="medium" className={styles.posterImageTitleText}>
            {image.fields.description}
          </Text>
        )}
      </Box>
      <button
        className={clsx('position-absolute top-0 left-0 width-full border-0', styles.playButton)}
        onClick={() => setIsPlaying(true)}
        aria-label={`Play video. Thumbnail description: ${image.fields.description || 'No description available'}`}
      >
        <PlayIcon className={styles.playIcon} />
      </button>
    </Box>
  )
}
