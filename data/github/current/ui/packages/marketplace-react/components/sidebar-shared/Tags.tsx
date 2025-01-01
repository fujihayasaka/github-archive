import {Stack} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import type {MarketplacePageTypes} from '../../types'
import {parameterize} from '../../utilities/parameterize'

interface TagsProps {
  tags: Array<{
    name: string
    slug: string
  }>
  type: MarketplacePageTypes
}

export function Tags(props: TagsProps) {
  const {tags, type} = props

  return (
    <>
      {tags && tags.length > 0 && (
        <Stack gap={'condensed'} data-testid={'tags'}>
          <SidebarHeading title="Tags" count={tags.length} htmlTag={'h2'} />
          <Stack direction={'horizontal'} wrap={'wrap'}>
            {tags.map(tag => {
              return (
                <a
                  href={`/marketplace?type=${type}&category=${tag.slug}`}
                  key={tag.slug}
                  className="topic-tag topic-tag-link"
                >
                  {parameterize(tag.name)}
                </a>
              )
            })}
          </Stack>
        </Stack>
      )}
    </>
  )
}
