import {Heading, Stack} from '@primer/react'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {useState, useRef} from 'react'
import styles from '../../marketplace.module.css'

export function Revealer({
  title,
  defaultOpen,
  children,
}: {
  title: string
  defaultOpen: boolean
  children: React.ReactNode
}) {
  const [showContent, setShowContent] = useState(defaultOpen)
  const detailsRef = useRef<HTMLDetailsElement>(null)

  // Sync state when the user clicks <summary>
  const handleToggle = () => {
    setShowContent(!!detailsRef.current?.open)
  }

  return (
    <details
      key={title}
      open={showContent}
      ref={detailsRef}
      onToggle={handleToggle}
      className={`border-top color-border-default pl-2 ${styles['marketplace-revealer']}`}
    >
      <Stack as="summary" gap="condensed" direction="horizontal" align="center" className="cursor-pointer my-3">
        {showContent ? (
          <ChevronDownIcon size={12} className="fgColor-muted" />
        ) : (
          <ChevronRightIcon size={12} className="fgColor-muted" />
        )}
        <Heading variant="small" as="h3">
          {title}
        </Heading>
      </Stack>
      {showContent && <div className="mb-3">{children}</div>}
    </details>
  )
}
