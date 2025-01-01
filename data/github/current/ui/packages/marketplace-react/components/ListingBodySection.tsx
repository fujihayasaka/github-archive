import {Stack} from '@primer/react'
import styles from './ListingBodySection.module.css'

interface ListingBodySectionProps {
  title: string
  id?: string
  'data-testid'?: string
  children?: React.ReactNode
}

export default function ListingBodySection({title, children, ...stackProps}: ListingBodySectionProps) {
  return (
    <Stack gap={{narrow: 'condensed', regular: 'normal'}} {...stackProps}>
      <h3 className={styles['section-title']}>{title}</h3>
      {children}
    </Stack>
  )
}
