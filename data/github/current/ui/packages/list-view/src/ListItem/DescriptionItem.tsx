import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import {type ComponentProps, useEffect, useRef} from 'react'

import {useListViewVariant} from '../ListView/VariantContext'
import {useListItemDescription} from './DescriptionContext'
import styles from './DescriptionItem.module.css'

export function ListItemDescriptionItem({children, className, ...props}: ComponentProps<'div'>) {
  const {variant} = useListViewVariant()
  const {setDescription} = useListItemDescription()
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (ref.current) {
      // Compose the ListItem description from the aria-label property of the DescriptionItem children
      const childrenAriaLabels = ref.current?.querySelectorAll('[aria-label]')
      let description = Array.from(childrenAriaLabels).reduce((metadataLabel: string, element: Element) => {
        return metadataLabel + element.getAttribute('aria-label')?.trim()
      }, '')
      if (!description && ref.current.textContent) description = ref.current.textContent.trim()
      setDescription(description)
    }
  }, [setDescription])

  return (
    <div
      ref={ref}
      {...testIdProps('list-view-item-descriptionitem')}
      {...props}
      className={clsx(styles.default, variant === 'compact' && styles.compact, className)}
    >
      {children}
    </div>
  )
}
