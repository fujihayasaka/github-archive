import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import {type PropsWithChildren, useEffect, useRef} from 'react'

import {useNestedListItemDescription} from './context/DescriptionContext'
import styles from './Description.module.css'

export interface DescriptionProps extends PropsWithChildren {
  className?: string
}

export const NestedListItemDescription = ({children, className}: DescriptionProps) => {
  const {setDescription} = useNestedListItemDescription()
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (ref.current) {
      // Compose the NestedListItem description from the aria-label property of the children
      const childrenAriaLabels = ref.current?.querySelectorAll('[aria-label]')
      let description = Array.from(childrenAriaLabels).reduce((metadataLabel: string, element: Element) => {
        return metadataLabel + element.getAttribute('aria-label')?.trim()
      }, '')
      if (!description && ref.current.textContent) description = ref.current.textContent.trim()
      setDescription(description)
    }
  }, [setDescription])

  return (
    <div className={clsx(styles.container, className)} {...testIdProps('nested-list-view-item-description')}>
      {children}
    </div>
  )
}
