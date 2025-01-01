import type React from 'react'
import type {DiffData, FileCategory} from '../utils/types'
import {DiffFile} from './DiffFile'
import {useHeadings} from '../utils/HeadingContext'
import {parseDiffsToHunks} from '../utils/parse-diffs-to-hunks'
import {useEffect} from 'react'
import styles from './OtherChanges.module.css'

// Format category name for display
function formatCategoryName(category: FileCategory): string {
  return category
    .split('_')
    .map(word => word.charAt(0) + word.slice(1).toLowerCase())
    .join(' ')
}

interface OtherChangesProps {
  nonProcessedDiffs: Record<FileCategory, DiffData[]>
}

export function OtherChanges({nonProcessedDiffs}: OtherChangesProps): React.ReactElement | null {
  const {addHeading} = useHeadings()

  // Filter out empty categories
  const categoriesToShow = Object.entries(nonProcessedDiffs).filter(([_, diffs]) => diffs && diffs.length > 0)

  // Add headings to the HeadingContext
  useEffect(() => {
    if (categoriesToShow.length > 0) {
      // Add the main "Other Changes" heading
      addHeading({
        id: 'other-changes',
        text: 'Other Changes',
        level: 2,
      })

      // Add each category as a subheading
      for (const [category] of categoriesToShow) {
        addHeading({
          id: `other-changes-${category.toLowerCase()}`,
          text: formatCategoryName(category as FileCategory),
          level: 3,
          parentId: 'other-changes',
        })
      }
    }
  }, [addHeading, categoriesToShow])

  if (categoriesToShow.length === 0) {
    return null
  }

  return (
    <div className={styles.container}>
      <h2 id="other-changes" className={styles.h2}>
        Other Changes
      </h2>

      {categoriesToShow.map(([category, diffs]) => (
        <div key={category} className={styles.categoryContainer}>
          <h3 id={`other-changes-${category.toLowerCase()}`} className={styles.h3}>
            {formatCategoryName(category as FileCategory)}
          </h3>

          {diffs.map(diff => {
            if (diff.isBinary || diff.isTooBig) {
              // Fixed accessibility issue by separating text elements properly
              const fileTypeLabel = diff.isBinary ? 'Binary file' : 'Too large to display'

              return (
                <div key={diff.path} className={styles.tooLarge}>
                  <div className={styles.label}>{fileTypeLabel}:</div>
                  <div className={styles.path}>{diff.path}</div>
                </div>
              )
            }
            const hunks = parseDiffsToHunks([diff])
            return (
              <div key={diff.path} className={styles.diffContainer}>
                <DiffFile fileName={diff.path} hunks={hunks} initiallyCollapsed />
              </div>
            )
          })}
        </div>
      ))}
    </div>
  )
}
