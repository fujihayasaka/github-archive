import {Link} from '@primer/react'
import styles from './JumpToBottom.module.css'
import {useEffect, useState} from 'react'

export function JumpToBottom() {
  const target = useJumpToBottomTarget()

  // Rare case: if we don't have a target, don't render the button
  if (!target) return null

  return (
    <Link className={styles.jumpToBottom} href={`#${target}`}>
      Jump to bottom
    </Link>
  )
}

/** Returns the ID string of the target for the 'jump to bottom' button */
export function useJumpToBottomTarget(): string | undefined {
  const [target, setTarget] = useState<string | undefined>('comment-composer-heading')
  const [initialized, setInitialized] = useState(false)

  // After initial render, check for the first 'jump to bottom' target, and then never run this effect again.
  // There is a chance this will cause the button to be hidden after it is initially rendered, but that case should
  // be rare, since we should always be rendering a target element on the page.
  useEffect(() => {
    if (!initialized) {
      const id = document.querySelector('[data-jump-to-bottom-target]')?.id
      setTarget(id)
      setInitialized(true)
    }
  }, [initialized])

  return target
}
