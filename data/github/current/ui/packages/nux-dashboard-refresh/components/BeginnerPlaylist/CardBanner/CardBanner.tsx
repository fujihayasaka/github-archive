import {IconButton, Heading, Label, LinkButton} from '@primer/react'
import {PlayIcon, XIcon} from '@primer/octicons-react'
import Pattern from './Pattern/Pattern'
import styles from './CardBanner.module.css'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface CardBannerProps {
  label?: string
  title: string
  description: string
  buttonText: string
  buttonHref: string
  caption?: string
  content?: React.ReactNode
  pattern?: boolean
  onDismiss?: () => void
}

export function CardBanner({
  label,
  title,
  description,
  buttonText,
  buttonHref,
  caption,
  content,
  pattern = false,
  onDismiss,
}: CardBannerProps) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  return (
    <div className={styles.cardWrapper}>
      <div className={styles.cardContainer}>
        <div>
          {label && <Label>{label}</Label>}
          <Heading as="h3" className={styles.title}>
            {title}
          </Heading>
          <p className={styles.description}>{description}</p>
          <LinkButton
            href={buttonHref}
            target="_blank"
            rel="noopener noreferrer"
            leadingVisual={PlayIcon}
            aria-label={title}
            onClick={() => {
              sendClickAnalyticsEvent({
                category: 'zero_user_dashboard',
                action: 'click.playlist.start_playlist',
              })
            }}
            data-testid="start-playlist"
          >
            {buttonText}
          </LinkButton>
          {caption && <p className="color-fg-muted mb-0 text-small">{caption}</p>}
        </div>
        {content}
      </div>

      {pattern && <Pattern />}

      {onDismiss && (
        <IconButton
          aria-label="Dismiss"
          data-testid={`${label}-dismiss`}
          size="small"
          variant="invisible"
          icon={XIcon}
          className={styles.dismissButton}
          onClick={onDismiss}
        />
      )}
    </div>
  )
}
