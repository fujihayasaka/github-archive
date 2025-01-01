import {clsx} from 'clsx'
import {memo, useState} from 'react'

import styles from './ChatImage.module.css'
import {ExpandIcon} from './icons/ExpandIcon'

export interface ChatImageProps {
  src: string
  alt?: string
  onClick?: React.MouseEventHandler
  useOverlay?: boolean
}

const ChatImageUnmemoized = ({src, alt, onClick, useOverlay}: ChatImageProps) => {
  const [isHovered, setIsHovered] = useState(false)

  return (
    <div className={styles.chatImageAttachment}>
      <img className={styles.userAttachedImage} src={src} alt={alt} />
      <a
        href={src}
        className={clsx(styles.overlay, {hovered: isHovered})}
        onClick={onClick}
        onMouseEnter={() => setIsHovered(true)}
        onMouseLeave={() => setIsHovered(false)}
        aria-label="Open image thumbnail"
        target="_blank"
        rel="noreferrer"
      >
        {useOverlay && (
          <>
            <div className={styles.overlayScreen} />
            <ExpandIcon className={styles.expandIcon} size={20} />
          </>
        )}
      </a>
    </div>
  )
}

export const ChatImage = memo(ChatImageUnmemoized)
