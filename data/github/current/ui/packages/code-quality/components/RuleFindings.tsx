import {codeQualityRuleFindingsPath} from '@github-ui/paths'
import {useRuleFindingsQuery} from '../hooks/use-rule-findings-query'
import pluralize from 'pluralize'
import {RuleFindingItem} from './RuleFindingItem'
import {useState} from 'react'
import type {Cursor} from '@github-ui/code-scanning-shared/types/cursor'
import {PrevNextPagination} from '@github-ui/code-scanning-shared/components/PrevNextPagination'
import {RuleFindingsLoading} from './RuleFindingsLoading'
import {ErrorState} from './ErrorState'

export interface RuleFindingsProps {
  owner: string
  repo: string
  ruleId: string
  fileCount: number
}

export function RuleFindings({owner, repo, ruleId, fileCount}: RuleFindingsProps) {
  const [cursor, setCursor] = useState<Cursor | null>(null)
  const ruleFindingsPath = codeQualityRuleFindingsPath({owner, repo, ruleId})
  const {data, isPending, isError} = useRuleFindingsQuery(ruleFindingsPath, {cursor})

  const ruleFindings = data?.ruleFindings || []
  const findingsCount = data?.findingsCount || 0

  if (isPending) {
    return (
      <div className="mt-3">
        <RuleFindingsLoading rowCount={5} />
      </div>
    )
  }
  if (isError) {
    return <ErrorState message="Rule findings data could not be loaded right now." />
  }

  return (
    <>
      <p className="mb-3 mt-3 f4 text-bold">
        Found {findingsCount} {pluralize('finding', findingsCount)} in {fileCount} {pluralize('file', fileCount)}
      </p>

      {ruleFindings.map(finding => (
        <RuleFindingItem
          key={`${finding.filePath}-${finding.startLine}`}
          snippetStartLine={finding.snippetStartLine}
          finding={finding}
        />
      ))}

      <PrevNextPagination onCursorChange={setCursor} prevCursor={data?.prevCursor} nextCursor={data?.nextCursor} />
    </>
  )
}
