import {useEffect, useId} from 'react'
import {InlineLink} from '@primer/react-brand'
import {clsx} from 'clsx'

import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {useFootnotes} from './FootnotesContext'
import type {InlineFootnote} from '../../../schemas/contentful/contentTypes/inlineFootnote'
import styles from './ContentfulInlineFootnote.module.css'

type ContentfulInlineFootnoteProps = {
  component: InlineFootnote
  analyticsLocation?: string
  providedInstanceId?: string
  size?: 'small' | 'large'
}

export function ContentfulInlineFootnote({
  component,
  analyticsLocation,
  providedInstanceId,
  size = 'small',
}: ContentfulInlineFootnoteProps) {
  const ctx = useFootnotes()
  const generatedInstanceId = useId()

  const cleanedProvidedId = providedInstanceId?.trim().slice(0, 20)
  const instanceId = cleanedProvidedId || generatedInstanceId

  useEffect(() => {
    if (!ctx) {
      return
    }
    ctx.registerFootnote(component, instanceId)
  }, [component, ctx, instanceId])

  if (!ctx) {
    return null
  }

  const nthIndex = ctx.getNthInstanceOfFootnote(component.sys.id, instanceId)
  const index = ctx.getFootnoteIndex(component.sys.id)

  if (index === -1 || nthIndex === -1) {
    return null
  }

  const referenceId = `${component.fields.anchorId}-ref-${nthIndex}`

  return (
    <sup>
      <InlineLink
        id={referenceId}
        href={`#${component.fields.anchorId}`}
        className={clsx(styles.footnoteInlineLink, {
          [styles.sizeSmall]: size === 'small',
          [styles.sizeLarge]: size === 'large',
        })}
        onClick={() => ctx.setLastClickedReferenceId(component.fields.anchorId, referenceId)}
        aria-label={`Footnote ${index + 1}`}
        {...getAnalyticsEvent({
          action: `inline footnote ${index + 1}`,
          tag: 'hyperlink',
          context: 'footnotes',
          location: analyticsLocation,
        })}
      >
        {index + 1}
      </InlineLink>
    </sup>
  )
}
