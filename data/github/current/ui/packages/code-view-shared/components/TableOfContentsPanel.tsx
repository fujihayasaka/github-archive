import type {TocEntry} from '@github-ui/code-view-types'
import {SafeHTMLBox} from '@github-ui/safe-html'
import {FilterIcon, XIcon} from '@primer/octicons-react'
import {IconButton, NavList, TextInput} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {onHashChange} from './SharedMarkdownContent'

import styles from './TableOfContentsPanel.module.css'

export default function TableOfContentsPanel({onClose, toc}: {onClose?: () => void; toc: TocEntry[] | null}) {
  const [filter, setFilter] = useState<string>('')
  const [hash, setHash] = useState<string>('')
  const headingRef = useRef<HTMLHeadingElement>(null)
  useEffect(() => {
    headingRef.current?.focus()
  }, [])

  useEffect(() => {
    const hashChange = () => {
      if (window.location.hash) {
        setHash(window.location.hash)
      }
    }

    hashChange()
    window.addEventListener('hashchange', hashChange)
    return () => {
      window.removeEventListener('hashchange', hashChange)
    }
  }, [])

  if (!toc) {
    return null
  }

  return (
    <section aria-labelledby="outline-id" className={styles.Box}>
      {onClose ? (
        <div className="d-flex flex-justify-between flex-items-center">
          <h3
            id="outline-id"
            ref={headingRef}
            className="d-flex flex-justify-between flex-items-center f5 text-bold px-2"
            tabIndex={-1}
          >
            Outline
          </h3>
          <IconButton
            aria-label="Close outline"
            tooltipDirection="sw"
            className="fgColor-muted"
            icon={XIcon}
            onClick={onClose}
            variant="invisible"
          />
        </div>
      ) : null}
      {toc.length >= 8 ? (
        <div className="pt-3 px-2">
          <TextInput
            leadingVisual={FilterIcon}
            placeholder="Filter headings"
            aria-label="Filter headings"
            className="width-full"
            onChange={e => {
              setFilter(e.target.value)
            }}
          />
        </div>
      ) : null}
      <NavList className={styles.NavList}>
        {toc.map(({level, htmlText, anchor}: TocEntry, index) => {
          if (!htmlText || (filter && !htmlText.toLowerCase().includes(filter.toLowerCase()))) {
            return null
          }
          let sx
          if (level === 1) {
            sx = {fontWeight: 'bold'}
          } else {
            sx = {paddingLeft: `${(level - 1) * 16}px`}
          }
          const hashString = `#${anchor}`
          return (
            <NavList.Item
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`outline-${anchor}-${index}`}
              aria-current={hash === hashString ? 'page' : undefined}
              href={hashString}
              onClick={e => {
                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (e.button === 1 || e.metaKey || e.ctrlKey) {
                  return
                }
                if (hash !== hashString) {
                  location.href = hashString
                }
                onHashChange(hashString)
                e.preventDefault()
              }}
            >
              <SafeHTMLBox sx={{...sx}} html={htmlText} />
            </NavList.Item>
          )
        })}
      </NavList>
    </section>
  )
}
