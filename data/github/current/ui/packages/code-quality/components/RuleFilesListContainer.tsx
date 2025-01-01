import {codeQualityRuleFilesPath} from '@github-ui/paths'
import {useRuleFilesQuery} from '../hooks/use-rule-files-query'
import type {RuleGroup} from '../types/rule-group'
import {RuleFilesList} from './RuleFilesList'

export type RuleFilesListContainerProps = {
  owner: string
  repo: string
  rule: RuleGroup
}

export function RuleFilesListContainer({owner, repo, rule}: RuleFilesListContainerProps) {
  const ruleFilesPath = codeQualityRuleFilesPath({owner, repo, ruleId: rule.ruleId})
  const {data, isPending, isError, error} = useRuleFilesQuery(ruleFilesPath)

  // For now we're just going to show loading and error states
  // but in the future we'll handle this better.
  if (isPending) {
    return <div>Loading...</div>
  }

  if (isError) {
    return <div>Error getting rules: {error.message}</div>
  }

  const ruleFiles = data?.files || []
  return <RuleFilesList owner={owner} repo={repo} rule={rule} files={ruleFiles} />
}
