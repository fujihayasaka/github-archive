import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {useResizeObserver} from '@primer/react'
import {useRef} from 'react'

import styles from './ContentEditor.module.css'
import {Autocomplete} from './Autocomplete'
import {useDebounce} from '@github-ui/use-debounce'
import {clsx} from 'clsx'

function useResponsiveTextArea(content: string) {
  const textAreaRef = useRef<HTMLTextAreaElement>(null)

  const adjustHeight = useDebounce(
    function adjustHeight() {
      if (!textAreaRef.current) return

      textAreaRef.current.style.height = '0'
      const scrollHeight = Math.min(textAreaRef.current.scrollHeight, 200)

      textAreaRef.current.style.height = `${scrollHeight}px`
    },
    50,
    {leading: true},
  )

  useLayoutEffect(() => {
    adjustHeight()
  }, [textAreaRef, content, adjustHeight])

  useResizeObserver(() => adjustHeight())

  return textAreaRef
}

export const ContentEditor = ({
  className,
  content,
  onUpdate,
  placeholder = 'Enter a prompt',
}: {
  className?: string
  content: string
  onUpdate?: (content: string) => void
  placeholder?: string
}) => {
  const textAreaRef = useResponsiveTextArea(content)

  return (
    <form className={clsx(styles.container, className)}>
      <Autocomplete>
        <textarea
          ref={textAreaRef}
          className={styles.input}
          autoComplete="off"
          autoCorrect="off"
          spellCheck="false"
          aria-multiline="true"
          onChange={e => onUpdate?.(e.target.value)}
          placeholder={placeholder}
          value={content}
        />
      </Autocomplete>
    </form>
  )
}
