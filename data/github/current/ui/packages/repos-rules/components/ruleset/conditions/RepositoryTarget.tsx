import type {FC} from 'react'
import type {
  ConditionParameters,
  RulesetTarget,
  RepositoryIdParameters,
  RepositoryIdConditionMetadata,
  IncludeExcludeParameters,
  RepositoryPropertyParameters,
  TargetType,
} from '../../../types/rules-types'
import {IncludeExcludeTarget} from './IncludeExcludeTarget'
import {RepositoryIdTarget} from './RepositoryIdTarget'
import {RepositoryPropertyTarget} from './RepositoryPropertyTarget'
import {isAllCondition} from '../../../helpers/conditions'
import {useRuleStrings} from '../../../hooks/use-rule-strings'

const PUSH_RULESET_TARGET_INFO = 'Push rulesets only apply to private repositories and their forks'

export type RepositoryTargetProps = {
  rulesetId?: number
  readOnly: boolean
  fnmatchHelpUrl?: string
  rulesetTarget: RulesetTarget
  targetType: TargetType
  parameters: ConditionParameters
  metadata?: object
  updateParameters: (parameters: ConditionParameters) => void
}

export const RepositoryTarget: FC<RepositoryTargetProps> = ({
  rulesetId,
  readOnly,
  fnmatchHelpUrl,
  rulesetTarget,
  targetType,
  parameters,
  metadata,
  updateParameters,
}) => {
  const target = isAllCondition(targetType, parameters) ? 'all_repos' : targetType
  const {rulesetOrPolicy} = useRuleStrings()

  return target === 'all_repos' && !readOnly ? null : (
    <div>
      {target === 'repository_name' || target === 'all_repos' ? (
        <IncludeExcludeTarget
          rulesetId={rulesetId}
          readOnly={readOnly}
          rulesetTarget={rulesetTarget}
          fnmatchHelpUrl={fnmatchHelpUrl}
          parameters={parameters as IncludeExcludeParameters}
          panelTitle="Targeting criteria"
          targetType="repository_name"
          updateParameters={updateParameters}
          headerRowText={rulesetTarget === 'push' ? PUSH_RULESET_TARGET_INFO : undefined}
          blankslate={{
            heading: 'No repository targets have been added yet',
          }}
        />
      ) : target === 'repository_id' ? (
        <RepositoryIdTarget
          readOnly={readOnly}
          parameters={parameters as RepositoryIdParameters}
          metadata={metadata as RepositoryIdConditionMetadata | undefined}
          updateParameters={updateParameters}
          headerRowText={rulesetTarget === 'push' ? PUSH_RULESET_TARGET_INFO : undefined}
          excludePublicRepos={rulesetTarget === 'push'}
          blankslate={{
            heading: 'No repository targets have been added yet',
            description: !readOnly ? (
              <>Repository targeting determines which repositories will be protected by this {rulesetOrPolicy}.</>
            ) : undefined,
          }}
        />
      ) : target === 'repository_property' ? (
        <RepositoryPropertyTarget
          readOnly={readOnly}
          parameters={parameters as RepositoryPropertyParameters}
          updateParameters={updateParameters}
          headerRowText={rulesetTarget === 'push' ? PUSH_RULESET_TARGET_INFO : undefined}
          rulesetTarget={rulesetTarget}
          blankslate={{
            heading: 'No repository targets have been added yet',
            description: !readOnly ? (
              <>Repository targeting determines which repositories will be protected by this {rulesetOrPolicy}.</>
            ) : undefined,
          }}
        />
      ) : undefined}
    </div>
  )
}
