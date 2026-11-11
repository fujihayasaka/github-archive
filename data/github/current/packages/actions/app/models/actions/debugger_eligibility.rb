# typed: true
# frozen_string_literal: true

class Actions::DebuggerEligibility
  sig { returns(T::Boolean) }
  def eligible?
    @reason == :allowed
  end

  sig { returns(Symbol) }
  attr_reader :reason

  sig { returns(String) }
  attr_reader :message

  sig do
    params(
      user: User,
      repository: Repository,
      workflow_run: Actions::WorkflowRun,
      check_run: CheckRun
    ).void
  end
  def initialize(user:, repository:, workflow_run:, check_run:)
    @reason = T.let(:allowed, Symbol)
    @message = T.let("", String)

    check_policy(repository)
    return unless eligible?

    check_fork_pr(check_run)
    return unless eligible?

    check_write_access(user, repository)
    return unless eligible?

    check_workflow_branch(user, repository, workflow_run)
    return unless eligible?

    check_reusable_workflows(user, repository, workflow_run)
    return unless eligible?

    check_required_workflows(user, workflow_run)
  end

  private

  sig { params(repository: Repository).void }
  def check_policy(repository)
    config = Actions::DebuggerPolicyConfig.new(repository)
    return if config.enabled?

    deny(:policy_disabled, "Only available when the job debugger is enabled for this repository. You can enable it in Settings > Actions > General > Job debugger.")
  end

  sig { params(check_run: CheckRun).void }
  def check_fork_pr(check_run)
    check_suite = check_run.check_suite
    return if check_suite.nil?
    return if check_suite.head_repository_id == check_suite.repository_id

    deny(:fork_pr, "Not available for workflow runs from fork pull requests")
  end

  sig { params(user: User, repository: Repository).void }
  def check_write_access(user, repository)
    return if repository.pushable_by?(user)

    deny(:no_write_access, "Only available for users with write access to this repository")
  end

  sig { params(user: User, repository: Repository, workflow_run: Actions::WorkflowRun).void }
  def check_workflow_branch(user, repository, workflow_run)
    branch = workflow_run.head_branch
    return if branch.nil?

    status = BranchRuleEvaluator.branch_commitability_status(repository, user, branch)
    return if status == :allowed

    deny(:branch_protected, "Only available for branches you can push to directly")
  end

  sig { params(user: User, repository: Repository, workflow_run: Actions::WorkflowRun).void }
  def check_reusable_workflows(user, repository, workflow_run)
    execution = workflow_run.latest_workflow_run_execution
    return unless execution

    loaded_execution = Actions::WorkflowRunExecution.with_referenced_workflows
      .find_by(id: execution.id, repository_id: execution.repository_id)
    return unless loaded_execution

    raw = loaded_execution.referenced_workflows
    return if raw.blank?

    workflows = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      return
    end
    workflows.each do |entry|
      ref = entry["ref"].to_s
      path = entry["path"].to_s

      if ref.blank? || ref.start_with?("refs/tags/")
        deny(:reusable_workflow_not_on_branch, "Only available for reusable workflows pinned to branches")
        return
      end

      branch = if ref.start_with?("refs/heads/")
        ref.delete_prefix("refs/heads/")
      else
        deny(:reusable_workflow_not_on_branch, "Only available for reusable workflows pinned to branches")
        return
      end

      nwo = path.split("/.github/").first
      source_repo = Repository.nwo(nwo)

      if source_repo.nil?
        deny(:reusable_workflow_inaccessible, "Only available when all reusable workflow repositories are accessible")
        return
      end

      if source_repo.id == repository.id
        status = BranchRuleEvaluator.branch_commitability_status(repository, user, branch)
        unless status == :allowed
          deny(:reusable_workflow_branch_protected, "Only available when you can push to the reusable workflow branch")
          return
        end
      else
        unless source_repo.pushable_by?(user) &&
            BranchRuleEvaluator.branch_commitability_status(source_repo, user, branch) == :allowed
          deny(:reusable_workflow_branch_protected, "Only available when you can push to the reusable workflow branch")
          return
        end
      end
    end
  end

  sig { params(user: User, workflow_run: Actions::WorkflowRun).void }
  def check_required_workflows(user, workflow_run)
    return unless workflow_run.imposer_repository_id > 0

    source_repo = Repositories::Public.find_active(workflow_run.imposer_repository_id)

    if source_repo.nil?
      deny(:required_workflow_inaccessible, "Only available when the required workflow repository is accessible")
      return
    end

    ref = workflow_run.workflow_file_ref.to_s
    unless ref.start_with?("refs/heads/")
      deny(:required_workflow_not_on_branch, "Only available for required workflows pinned to branches")
      return
    end

    branch = ref.delete_prefix("refs/heads/")

    unless source_repo.pushable_by?(user) &&
        BranchRuleEvaluator.branch_commitability_status(source_repo, user, branch) == :allowed
      deny(:required_workflow_branch_protected, "Only available when you can push to the required workflow branch")
    end
  end

  sig { params(reason: Symbol, message: String).void }
  def deny(reason, message)
    @reason = reason
    @message = message
  end
end
