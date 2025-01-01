import {PlayIcon} from '@primer/octicons-react'
import styles from './VideoPreview.module.css'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface VideoPreviewProps {
  href: string
  imageSrc: string
  imageAlt?: string
  ariaLabel?: string
}

export function VideoPreview({
  href,
  ariaLabel = 'Watch video',
  imageSrc,
  imageAlt = 'Video thumbnail',
}: VideoPreviewProps) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <a
      className={styles.videoPreview}
      href={href}
      target={'_blank'}
      aria-label={ariaLabel}
      rel="noopener noreferrer"
      onClick={() => {
        sendClickAnalyticsEvent({
          category: 'zero_user_dashboard',
          action: 'click.playlist.play_video',
        })
      }}
      data-testid="play-video"
    >
      <img className="d-block rounded-2 width-full" src={imageSrc} alt={imageAlt} />
      <div className={styles.playButtonIcon}>
        <PlayIcon size={32} />
      </div>
    </a>
  )
}
