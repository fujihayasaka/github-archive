import {useState} from 'react'
import type {ReactNode} from 'react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {CopyIcon, ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import styles from './InputSection.module.css'
import {clsx} from 'clsx'

interface InputSectionLayoutProps {
  additionalFields?: ReactNode
  content: string | null | undefined
  contentEditor: ReactNode
  children?: ReactNode
  inputLabelId?: string
}

export function InputSectionLayout({
  additionalFields,
  content,
  contentEditor,
  children,
  inputLabelId,
}: InputSectionLayoutProps) {
  const [isExpanded, setIsExpanded] = useState(true)

  return (
    <div className={styles.container}>
      {additionalFields}
      <div className={styles.nodeInput}>
        <div className={styles.header}>
          <Button
            leadingVisual={isExpanded ? ChevronDownIcon : ChevronRightIcon}
            aria-label={isExpanded ? 'Collapse input section' : 'Expand input section'}
            onClick={() => setIsExpanded(!isExpanded)}
            variant="invisible"
            size="small"
            id={inputLabelId}
            className={clsx(styles.groupTitle, styles.button)}
          >
            Input
          </Button>
          <CopyToClipboardButton
            icon={CopyIcon}
            variant="invisible"
            ariaLabel="Copy input"
            textToCopy={content ? content.toString() : ''}
          />
        </div>
        {isExpanded && (
          <>
            {contentEditor}
            {children}
          </>
        )}
      </div>
    </div>
  )
}
