import {Dialog} from '@primer/react'

import styles from './FilteredContentModal.module.css'

interface FilteredContentModalProps {
  content: string | null
  filteredCategories?: Array<{category: string; severity: string}>
  onClose: () => void
}

export function FilteredContentModal({content, filteredCategories, onClose}: FilteredContentModalProps) {
  const renderFilteredCategories = () => {
    if (!filteredCategories || filteredCategories.length === 0) return null

    return (
      <ul className={styles['content-list']}>
        {filteredCategories.map((category, _) => (
          <li key={category.category}>
            <strong>{category.category}</strong>
          </li>
        ))}
      </ul>
    )
  }

  return (
    <Dialog title="Content Filtered" onClose={onClose} aria-labelledby="filtered-modal-title">
      <div className={styles.content}>
        {filteredCategories && filteredCategories.length > 0 ? (
          <>
            <p>The generated code was filtered for containing content that matched the following categories:</p>
            {renderFilteredCategories()}
            <br />
            <p>We have returned your spark to its previous state.</p>
          </>
        ) : (
          content
        )}
      </div>
    </Dialog>
  )
}
