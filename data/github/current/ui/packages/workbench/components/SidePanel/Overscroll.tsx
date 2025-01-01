import {clsx} from 'clsx'
import {type MutableRefObject, useEffect, useState} from 'react'

import styles from './Overscroll.module.css'

type OverscrollProps = {
  scrollingRef: MutableRefObject<HTMLDivElement | null>
}

export const Overscroll = ({scrollingRef}: OverscrollProps) => {
  const [isScrolled, setScrolled] = useState(false)
  useEffect(() => {
    const onScroll = (e: Event) => {
      const target = e.currentTarget as HTMLElement
      if (target.scrollTop > 0) {
        setScrolled(true)
      } else {
        setScrolled(false)
      }
    }
    const container = scrollingRef.current
    // eslint-disable-next-line github/prefer-observers
    container?.addEventListener('scroll', onScroll)

    return () => {
      container?.removeEventListener('scroll', onScroll)
    }
  }, [scrollingRef])

  return <div className={clsx(styles.overscroll, {[styles.showOverscroll]: isScrolled})} />
}
