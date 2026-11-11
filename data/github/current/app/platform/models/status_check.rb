# typed: true
# frozen_string_literal: true

class Platform::Models::StatusCheck
  include GitHub::Relay::GlobalIdentification
  attr_reader :status, :repository_id, :pull_request

  sig do
    params(
      status: PullRequests::PageData::StatusChecksSerializer::StatusCheckModel,
      repository_id: Integer,
      pull_request: T.nilable(PullRequest)
    ).void
  end
  def initialize(status:, repository_id:, pull_request: nil)
    @status = status
    @repository_id = repository_id
    @pull_request = pull_request
  end

  def self.load_from_global_id(id)
    parts = id.split(":", 4)
    load_unified_format(parts)
  end

  def id
    case @status
    when PullRequests::External::StatusCheckFinder::Record
      # Transform class name to type prefix using check_type
      type_prefix = case @status.check_type
      when "Status" then "status"
      when "CombinedStatus::CheckRunAdapter" then "check_run"
      when "RequiredStatusCheck" then "required"
      when "InMemoryRequiredStatusCheck"
        @status.protected_branch_backed? ? "required" : "memory"
      when "RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType" then "workflow"
      else
        raise Platform::Errors::NotFound, "Unsupported status check type: #{@status.check_type}"
      end

      "#{type_prefix}:#{@repository_id}:#{@status.identifier}"
    when ::Status
      "status:#{@repository_id}:#{@status.id}"
    when CombinedStatus::CheckRunAdapter
      "check_run:#{@repository_id}:#{@status.id}"
    when ::RequiredStatusCheck
      "required:#{@repository_id}:#{@status.id}"
    when InMemoryRequiredStatusCheck
      if @status.protected_branch_backed?
        # For ProtectedBranch-backed checks, use the underlying RequiredStatusCheck's ID
        "required:#{@repository_id}:#{T.must(@status.status_check).id}"
      else
        # For Ruleset-backed checks, use rule_config.id and context_hash
        "memory:#{@repository_id}:#{@status.rule_config.id}:#{@status.context_hash}"
      end
    else
      if @status.respond_to?(:check_suite)
        "workflow:#{@repository_id}:#{@status.check_suite&.id || 'unknown'}"
      else
        raise Platform::Errors::NotFound, "Unsupported status check type: #{@status.class}"
      end
    end
  end

  class << self
    private

    def load_unified_format(parts)
      type = parts[0]
      repo_id = parts[1]&.to_i

      case type
      when "status"
        load_status_check(repo_id, parts[2].to_i)
      when "check_run"
        load_check_run_check(repo_id, parts[2].to_i)
      when "required"
        load_required_status_check(repo_id, parts[2].to_i)
      when "memory"
        load_in_memory_required_status_check(repo_id, parts[2].to_i, parts[3])
      when "workflow"
        Promise.resolve(nil)
      else
        raise Platform::Errors::NotFound, "Unknown status check type: #{type}"
      end
    end

    def load_status_check(repo_id, status_id)
      Platform::Loaders::ActiveRecord.load(::Status, status_id).then do |status|
        next nil unless status && status.repository_id == repo_id
        new(status: status, repository_id: repo_id)
      end
    end

    def load_check_run_check(repo_id, check_run_id)
      Platform::Loaders::ActiveRecord.load(::CheckRun, check_run_id).then do |check_run|
        next nil unless check_run && check_run.repository_id == repo_id
        adapter = CombinedStatus::CheckRunAdapter.new(check_run)
        new(status: adapter, repository_id: repo_id)
      end
    end

    def load_required_status_check(repo_id, required_status_id)
      Platform::Loaders::ActiveRecord.load(::RequiredStatusCheck, required_status_id).then do |required_check|
        next nil unless required_check
        required_check.async_repository.then do |repository|
          next nil unless repository && repository.id == repo_id
          new(status: required_check, repository_id: repo_id)
        end
      end
    end

    def load_in_memory_required_status_check(repo_id, rule_config_id, context_hash)
      Platform::Objects::RequiredStatusCheck.load_rule_config_check(
        repo_id, rule_config_id, context_hash
      ).then do |required_status_check|
        next nil unless required_status_check
        in_memory_check = if required_status_check.respond_to?(:__getobj__)
          required_status_check.__getobj__
        else
          required_status_check
        end
        new(status: in_memory_check, repository_id: repo_id)
      end
    end
  end
end
