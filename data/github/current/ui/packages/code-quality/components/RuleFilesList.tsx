import {ListView} from '@github-ui/list-view'
import type {RuleFile} from '../types/rule-file'
import type {RuleGroup} from '../types/rule-group'
import {RuleFileListItem} from './RuleFileListItem'
import {RuleFileListMoreItem} from './RuleFileListMoreItem'

export type RuleFilesListProps = {
  owner: string
  repo: string
  rule: RuleGroup
  files: RuleFile[]
}

export function RuleFilesList({owner, repo, rule, files}: RuleFilesListProps) {
  const findingsCountInFiles = files.reduce((acc, file) => acc + file.findingsCount, 0)
  const remainingFindingsCount = rule.findingsCount - findingsCountInFiles

  return (
    <ListView title="Files affected by this rule">
      {files.map(file => (
        <RuleFileListItem key={file.filePath} file={file} />
      ))}
      {remainingFindingsCount > 0 && (
        <RuleFileListMoreItem
          owner={owner}
          repo={repo}
          ruleId={rule.ruleId}
          remainingFindingsCount={remainingFindingsCount}
        />
      )}
    </ListView>
  )
}
