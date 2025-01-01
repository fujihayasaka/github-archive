import {Spinner} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef, useState} from 'react'

import {referenceName, referenceURL} from '../utils/copilot-chat-helpers'
import type {FigmaReference} from '../utils/copilot-chat-types'
import styles from './FigmaChatReference.module.css'
import {FigmaIcon} from './icons/FigmaIcon'

interface FigmaChatReferenceProps {
  reference: FigmaReference
  onClick?: React.MouseEventHandler<HTMLAnchorElement>
}

export const FigmaChatReference = forwardRef<HTMLAnchorElement, FigmaChatReferenceProps>(function ReferenceToken(
  {reference, ...rest},
  ref,
) {
  const [thumbnailIsLoading, setThumbnailIsLoading] = useState(true)

  return (
    <>
      <a
        href={referenceURL(reference)}
        className={clsx(styles.referenceToken)}
        ref={ref}
        target="_blank"
        rel="noreferrer"
        {...rest}
      >
        <span className={styles.thumbnailOuter}>
          {reference.thumbnailUrl && (
            <>
              {thumbnailIsLoading && (
                <span className={styles.thumbnailLoading}>
                  <Spinner size="medium" />
                </span>
              )}
              <img
                className={clsx(styles.thumbnail, {[styles.thumbnailHidden]: thumbnailIsLoading})}
                src={reference.thumbnailUrl}
                alt={`preview thumbnail for ${reference.title}`}
                onLoad={() => setThumbnailIsLoading(false)}
              />
            </>
          )}
        </span>
        <span className={styles.content}>
          <div className={styles.figmaIconOuter}>
            <FigmaIcon className={styles.figmaIcon} />
          </div>
          <span className={styles.name}>{referenceName(reference)}</span>
        </span>
      </a>
    </>
  )
})
