import {keepPreviousData, useQuery} from '@github-ui/react-query'
import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {StopIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {clsx} from 'clsx'
import throttle from 'lodash-es/throttle'
import {useEffect, useMemo, useState} from 'react'

import type {File} from './content-preview-types'
import styles from './MarkdownPreview.module.css'

interface MarkdownResponse {
  html: SafeHTMLString
}

export function MarkdownPreview({file}: {file: File}) {
  const throttledValue = useThrottledValue(file.value, 2000)
  const {status, data} = useQuery({
    queryKey: ['copilot-immersive', 'MarkdownPreview', throttledValue, file.name],
    queryFn: async () => {
      const res = await verifiedFetchJSON('/copilot/immersive/markdown', {
        method: 'POST',
        body: {content: throttledValue, filename: file.name},
      })
      if (!res.ok) {
        throw new Error(`Failed to load rendered markdown (${res.status} on ${res.url})`)
      }
      const value = await res.json()
      return value as MarkdownResponse
    },
    placeholderData: keepPreviousData,
    staleTime: Infinity,
  })

  return (
    <div className={clsx('readme html-blob blob', styles.markdownPreview)}>
      {status === 'pending' ? (
        <div className={styles.spinner}>
          <Spinner srText="Loading Markdown preview…" />
        </div>
      ) : status === 'error' ? (
        <div className={styles.error}>
          <span className={styles.errorIcon}>
            <StopIcon size={24} />
          </span>
          <h2 className={styles.errorHeader}>Markdown rendering failed</h2>
          <p>Refresh the page or check the markdown code</p>
        </div>
      ) : (
        <SafeHTMLDiv className="markdown-body" html={data.html} />
      )}
    </div>
  )
}

/**
 * Returns the value given to it, eventually. The return value changes at most every delay milliseconds.
 */
function useThrottledValue<T>(value: T, delay: number) {
  const [throttledValue, setThrottledValue] = useState(value)
  const throttledSetter = useMemo(() => throttle(setThrottledValue, delay), [delay])
  useEffect(() => throttledSetter(value), [throttledSetter, value])
  return throttledValue
}
