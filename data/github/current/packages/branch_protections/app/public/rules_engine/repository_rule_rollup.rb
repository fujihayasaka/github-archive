# typed: strict
# frozen_string_literal: true

class RulesEngine::RepositoryRuleRollup

  class RuleType < T::Enum
    enums do
      Creation = new("CREATION")
      Update = new("UPDATE")
      Deletion = new("DELETION")
      RequireLinearHistory = new("REQUIRED_LINEAR_HISTORY")
      MergeQueue = new("MERGE_QUEUE")
      RequiredReviewThreadResolution = new("REQUIRED_REVIEW_THREAD_RESOLUTION")
      RequiredDeployments = new("REQUIRED_DEPLOYMENTS")
      RequiredSignatures = new("REQUIRED_SIGNATURES")
      PullRequest = new("PULL_REQUEST")
      RequiredStatusChecks = new("REQUIRED_STATUS_CHECKS")
      RequiredWorkflowStatusChecks = new("REQUIRED_WORKFLOW_STATUS_CHECKS")
      NonFastFoward = new("NON_FAST_FORWARD")
      Authorization = new("AUTHORIZATION")
      Tag = new("TAG")
      MergeQueueLockedRef = new("MERGE_QUEUE_LOCKED_REF")
      LockBranch = new("LOCK_BRANCH")
      MaxRefUpdates = new("MAX_REF_UPDATES")
      CommitMessagePattern = new("COMMIT_MESSAGE_PATTERN")
      CommitAuthorEmailPattern = new("COMMIT_AUTHOR_EMAIL_PATTERN")
      CommitterEmailPattern = new("COMMITTER_EMAIL_PATTERN")
      BranchNamePattern = new("BRANCH_NAME_PATTERN")
      TagNamePatten = new("TAG_NAME_PATTERN")
      FilePathRestriction = new("FILE_PATH_RESTRICTION")
      MaxFilePathLength = new("MAX_FILE_PATH_LENGTH")
      FileExtensionRestriction = new("FILE_EXTENSION_RESTRICTION")
      MaxFileSize = new("MAX_FILE_SIZE")
      CommitOid = new("COMMIT_OID")
      Workflows = new("WORKFLOWS")
      SecretScanning = new("SECRET_SCANNING")
      WorkflowUpdates = new("WORKFLOW_UPDATES")
      CodeScanning = new("CODE_SCANNING")
      RestrictRepoDelete = new("REPOSITORY_DELETE")
      RepositoryTransfer = new("REPOSITORY_TRANSFER")
      RestrictRepositoryName = new("REPOSITORY_NAME")
      RepositoryCreate = new("REPOSITORY_CREATE")
    end
  end

  class RuleRollupResult < T::Enum
    enums do
      Passed = new("PASSED")
      Failed = new("FAILED")
    end
  end

  class RuleRollupPayload < T::Struct
    const :ruleType, RuleType
    const :displayName, String
    const :message, T.nilable(String)
    const :result, RuleRollupResult
    const :bypassable, T::Boolean
    const :metadata, T.nilable(RulesEngine::RuleRollups::RuleRollupMetadata::RuleSpecificMetadata)
  end

  sig { returns(String) }
  attr_reader :rule_type

  sig { returns(RuleEngine::BaseRule) }
  attr_reader :rule_impl

  delegate :created_at, :updated_at, :repository, :async_repository, to: :@rule_suite

  sig { params(rule_suite: RuleEngine::RuleSuite, rule_type: String).void }
  def initialize(rule_suite, rule_type)
    @rule_suite = rule_suite
    @rule_type = rule_type

    rule_impl = RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
    raise ArgumentError, "Unknown rule type #{rule_type}" unless rule_impl
    @rule_impl = T.let(rule_impl, RuleEngine::BaseRule)
  end

  sig { returns(T.nilable(String)) }
  def platform_type_name
    case rule_type
    when "required_deployments"
      "RequiredDeploymentsRuleRollup"
    when "pull_request"
      "PullRequestRuleRollup"
    when "required_status_checks"
      "RequiredStatusChecksRuleRollup"
    else
      "GenericRepositoryRuleRollup"
    end
  end

  sig { returns(String) }
  def display_name
    rule_impl.display_name
  end

  sig { returns(T.nilable(String)) }
  def description
    rule_impl.description
  end

  sig { returns(String) }
  def result
    rule_runs.all?(&:allowed?) ? "passed" : "failed"
  end

  sig { returns(String) }
  def message
    rule_runs.filter(&:failed?).map(&:message).compact.uniq.reject(&:empty?).join(",")
  end

  sig { returns(T::Boolean) }
  def bypassable
    @rule_suite.can_bypass_rule_type?(rule_type)
  end

  sig { returns(T::Enumerable[RuleEngine::RuleRun]) }
  def rule_runs
    @rule_suite.rule_runs.select { |run| run.rule_type == rule_type }
  end

  sig { returns(RuleRollupPayload) }
  def payload
    RuleRollupPayload.new(
      ruleType: RuleType.deserialize(rule_type.upcase),
      displayName: display_name,
      message: GitHub::Goomba::PullRequestMergeConditionMessagePipeline.to_html(message),
      result: RuleRollupResult.deserialize(result.upcase),
      bypassable: bypassable,
      metadata: metadata&.payload
    )
  end

  sig { returns(T.nilable(RulesEngine::RuleRollups::RuleRollupMetadata)) }
  def metadata
    case rule_type
    when "pull_request"
      RulesEngine::RuleRollups::PullRequestRollupMetadata.new(@rule_suite)
    when "required_status_checks"
      RulesEngine::RuleRollups::RequiredStatusCheckRollupMetadata.new(@rule_suite)
    when "required_deployments"
      RulesEngine::RuleRollups::RequiredDeploymentRollupMetadata.new(@rule_suite)
    else
      nil
    end
  end

end
