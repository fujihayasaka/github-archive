import {testIdProps} from '@github-ui/test-id-props'
import {Box} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import type {Labels} from './types'

interface TagsSectionProps {
  labels: Labels
  headingLevel?: 'h2' | 'h3'
}

export function TagsSection({labels, headingLevel = 'h3'}: TagsSectionProps) {
  const {tags, task} = labels

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        width: '100%',
        gap: 2,
      }}
      {...testIdProps('tags-section')}
    >
      <SidebarHeading htmlTag={headingLevel} title="Tags" count={task ? tags.length + 1 : tags.length} />
      {(tags.length > 0 || task) && (
        <Box sx={{display: 'flex', gap: 2, flexWrap: 'wrap'}}>
          {tags.map(tag => {
            // categories cannot contain `-` characters, or ES wil analyze them as separate words
            const category = tag.toLowerCase().split('-')[0]

            return (
              <a href={`/marketplace?type=models&category=${category}`} key={tag} className="topic-tag topic-tag-link">
                {tag}
              </a>
            )
          })}

          {task && (
            <a href={`/marketplace?type=models&task=${task}`} key={task} className="topic-tag topic-tag-link">
              {task}
            </a>
          )}
        </Box>
      )}
    </Box>
  )
}
