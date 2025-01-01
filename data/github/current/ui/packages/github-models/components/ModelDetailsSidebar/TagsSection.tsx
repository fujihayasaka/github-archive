import {testIdProps} from '@github-ui/test-id-props'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import type {Labels} from '../../routes/playground/components/types'
import styles from './TagsSection.module.css'
import {modelsCatalogPath} from '@github-ui/paths'

interface TagsSectionProps {
  labels: Labels
  headingLevel?: 'h2' | 'h3'
}

export function TagsSection({labels: {tags, task}, headingLevel = 'h3'}: TagsSectionProps) {
  return (
    <div className={styles.tagsSection} {...testIdProps('tags-section')}>
      <SidebarHeading htmlTag={headingLevel} title="Tags" count={task ? tags.length + 1 : tags.length} />
      {(tags.length > 0 || task) && (
        <div className={styles.categories}>
          {tags.map(tag => {
            return (
              <a href={modelsCatalogPath({category: tag})} key={tag} className="topic-tag topic-tag-link" tabIndex={0}>
                {tag}
              </a>
            )
          })}

          {task && (
            <a href={modelsCatalogPath({task})} key={task} className="topic-tag topic-tag-link" tabIndex={0}>
              {task}
            </a>
          )}
        </div>
      )}
    </div>
  )
}
