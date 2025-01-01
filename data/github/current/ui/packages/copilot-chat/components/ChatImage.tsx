import {clsx} from 'clsx'
import {memo, useState} from 'react'

import type {CopilotChatMode} from '../utils/copilot-chat-types'
import styles from './ChatImage.module.css'
import {ExpandIcon} from './icons/ExpandIcon'

export interface ChatImageProps {
  src: string
  alt?: string
  onClick?: React.MouseEventHandler
  useOverlay?: boolean
  squareView?: boolean
  mode: CopilotChatMode
}

const ChatImageUnmemoized = ({src, alt, onClick, useOverlay, mode, squareView}: ChatImageProps) => {
  const [isHovered, setIsHovered] = useState(false)

  return (
    <div
      className={clsx(styles.chatImageAttachment, squareView ? styles.squareView : styles.fullView, {
        assistive: mode === 'assistive',
      })}
    >
      <img
        className={clsx(styles.userAttachedImage, squareView ? styles.squareView : styles.fullView)}
        src={src}
        alt={alt}
      />
      <a
        href={src}
        className={clsx(styles.overlay, {hovered: isHovered, [styles.squareView]: squareView})}
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
