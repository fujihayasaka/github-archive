import {ListItem} from '@github-ui/list-view/ListItem'

import {Link} from '@primer/react'
import {codeQualityShowPath} from '@github-ui/paths'

export type RuleFileListMoreItemProps = {
  owner: string
  repo: string
  ruleId: string
  remainingFindingsCount: number
}

export function RuleFileListMoreItem({owner, repo, ruleId, remainingFindingsCount}: RuleFileListMoreItemProps) {
  return (
    <ListItem
      title={
        <Link
          href={codeQualityShowPath({owner, repo, ruleId})}
          className="no-wrap d-block overflow-hidden text-overflow-ellipsis pt-2 pl-2"
        >
          {remainingFindingsCount > 1 ? `and ${remainingFindingsCount} more findings` : 'and 1 more finding'}
        </Link>
      }
    />
  )
}
