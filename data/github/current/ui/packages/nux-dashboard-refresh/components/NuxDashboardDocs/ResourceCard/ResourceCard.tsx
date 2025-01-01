import {BookIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import type React from 'react'
import styles from './ResourceCard.module.css'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface ResourceCardProps {
  icon?: React.ReactNode
  title: string
  description?: string
  readTime?: number
  href: string
}

export const ResourceCard = ({icon, title, description, readTime, href}: ResourceCardProps) => {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const descriptionText = readTime ? `Read · Est. ${readTime}m` : description

  // Turns title into a lowercase string with underscores and removes non-word characters
  const sanitizedTitle = title
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^\w_]/g, '')

  return (
    <Link
      href={href}
      className={styles.link}
      target="_blank"
      rel="noopener noreferrer"
      onClick={() => {
        sendClickAnalyticsEvent({
          category: 'zero_user_dashboard',
          action: `click.docs.resource_card.${sanitizedTitle}`,
        })
      }}
      data-testid={`resource-card-${sanitizedTitle}`}
    >
      {icon || <BookIcon size={24} />}
      <div className={styles.resourceCardContent}>
        <div className="mt-2 text-bold">{title}</div>
        {descriptionText ? (
          <div className="color-fg-muted mt-auto text-small">{readTime ? `Read · Est. ${readTime}m` : description}</div>
        ) : null}
      </div>
    </Link>
  )
}
