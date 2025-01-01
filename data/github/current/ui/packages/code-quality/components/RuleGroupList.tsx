import {useCallback, useState} from 'react'
import type {RuleGroup} from '../types/rule-group'
import {ListView} from '@github-ui/list-view'
import {RuleGroupListItem} from './RuleGroupListItem'
import {RuleFilesListContainer} from './RuleFilesListContainer'
import {codeQualityRulesPath} from '@github-ui/paths'
import {useRuleGroupsQuery} from '../hooks/use-rule-groups-query'
import styles from './RuleGroupList.module.css'
import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'
import {PrevNextPagination} from '@github-ui/code-scanning-shared/components/PrevNextPagination'
import {RulesLoading} from './RulesLoading'
import {ErrorState} from './ErrorState'

export interface RuleGroupListProps {
  owner: string
  repo: string
  findingsCount: number
}

export function RuleGroupList({owner, repo, findingsCount}: RuleGroupListProps) {
  const [isExpanded, setIsExpanded] = useState<{[key: string]: boolean}>({})
  const toggleExpanded = useCallback(
    (expandedGroup: string) => {
      setIsExpanded(prev => ({
        ...prev,
        [expandedGroup]: !prev[expandedGroup],
      }))
    },
    [setIsExpanded],
  )

  const [cursor, setCursor] = useState<Cursor | null>(null)
  const rulesPath = codeQualityRulesPath({owner, repo})
  const {data, isPending, isError} = useRuleGroupsQuery(rulesPath, {cursor})

  // For now we're just going to show loading and error states
  // but in the future we'll handle this better.
  if (isPending) {
    return <RulesLoading rowCount={5} />
  }
  if (isError) {
    return <ErrorState message="Rules data could not be loaded right now." />
  }

  const groups = data?.rules || []

  return (
    <>
      <div className={styles.container}>
        <ListView title="Findings" titleHeaderTag="h3" totalCount={findingsCount}>
          {groups.map((ruleGroup: RuleGroup) => (
            <RuleGroupListItem
              owner={owner}
              repo={repo}
              key={ruleGroup.title}
              group={ruleGroup}
              expanded={isExpanded[ruleGroup.title] || false}
              onExpandedChange={toggleExpanded}
              renderGroup={(rg: RuleGroup) => <RuleFilesListContainer owner={owner} repo={repo} rule={rg} />}
            />
          ))}
        </ListView>
      </div>
      <PrevNextPagination onCursorChange={setCursor} prevCursor={data?.prevCursor} nextCursor={data?.nextCursor} />
    </>
  )
}
