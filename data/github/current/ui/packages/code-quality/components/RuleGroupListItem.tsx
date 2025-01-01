import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {CounterLabel, IconButton} from '@primer/react'
import type {RuleGroup} from '../types/rule-group'

import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {useCallback} from 'react'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {RuleCategoryBadge} from './RuleCategoryBadge'
import {RuleSeverityBadge} from './RuleSeverityBadge'

import styles from './RuleGroupListItem.module.css'
import {codeQualityShowPath} from '@github-ui/paths'

export interface RuleGroupListItemProps {
  owner: string
  repo: string
  group: RuleGroup
  expanded: boolean
  onExpandedChange?: (group: string) => void
  renderGroup: (group: RuleGroup) => React.ReactNode
}

export function RuleGroupListItem({
  owner,
  repo,
  group,
  expanded,
  onExpandedChange,
  renderGroup,
}: RuleGroupListItemProps) {
  const onToggle = useCallback(() => {
    onExpandedChange?.(group.title)
  }, [onExpandedChange, group.title])

  const toggleOnKeyDown = (event: React.KeyboardEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if ((event.key === 'ArrowLeft' && expanded) || (event.key === 'ArrowRight' && !expanded)) {
      onToggle()
    }
  }

  return (
    <>
      <ListItem
        title={
          <ListItemTitle
            value={group.title}
            href={codeQualityShowPath({owner, repo, ruleId: group.ruleId})}
            trailingBadges={[
              <CounterLabel key={0} className="ml-2">
                {group.findingsCount}
              </CounterLabel>,
            ]}
            headingClassName={styles.title}
          />
        }
        className={styles.container}
        metadata={
          <ListItemMetadata>
            <RuleCategoryBadge category={group.category} />
            <RuleSeverityBadge severity={group.severity} />
          </ListItemMetadata>
        }
      >
        <ListItemLeadingContent className={styles.leadingContent}>
          <IconButton
            aria-label={`Toggle ${group.title}`}
            icon={expanded ? ChevronDownIcon : ChevronRightIcon}
            variant="invisible"
            size="large"
            onClick={onToggle}
            onKeyDown={toggleOnKeyDown}
          />
        </ListItemLeadingContent>
      </ListItem>
      {expanded && renderGroup(group)}
    </>
  )
}
