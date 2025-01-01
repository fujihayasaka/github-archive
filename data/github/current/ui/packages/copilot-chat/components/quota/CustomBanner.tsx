import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import type {ReactNode} from 'react'
import {useEffect, useRef, useState} from 'react'

import styles from './CustomBanner.module.css'

interface CustomBannerProps {
  icon: ReactNode
  content: ReactNode
  actions: ReactNode
  onDismiss?: () => void
}

export function CustomBanner({icon, content, actions, onDismiss}: CustomBannerProps) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const [isExpanded, setIsExpanded] = useState(false)

  useEffect(() => {
    const container = containerRef.current

    if (!container) return

    const resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        if (entry.target === container) {
          if (entry.contentRect.height > 40) {
            setIsExpanded(true)
          } else {
            setIsExpanded(false)
          }
        }
      }
    })
    resizeObserver.observe(container)
    return () => {
      resizeObserver.disconnect()
    }
  }, [])

  return (
    <div ref={containerRef} className={`${styles.container} ${isExpanded ? styles.expanded : ''}`}>
      <div className={styles.icon}>{icon}</div>
      <div className={styles.content}>{content}</div>
      <div className={styles.actions}>
        {actions}
        {onDismiss && (
          <IconButton
            className={styles.iconButton}
            variant="invisible"
            icon={XIcon}
            size="medium"
            aria-label="Close"
            onClick={onDismiss}
          />
        )}
      </div>
    </div>
  )
}
