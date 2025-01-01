# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class Actions::TriggerTypes
  include GitHub::Memoizer
  include Repositories::Domain::Provider

  DEPLOYMENT = :deployment
  ISSUE = :issue
  ISSUE_COMMENT = :issue_comment
  MERGE_GROUP = :merge_group
  PULL_REQUEST = :pull_request
  PUSH = :push
  RELEASE = :release
  SCHEDULE = :schedule
  REPOSITORY_DISPATCH = :repository_dispatch
  WORKFLOW_DISPATCH = :workflow_dispatch
  RETRY = :retry
  OTHER = :other

  def self.call(
    workflow_run:,
    triggered_by_retry: false
  )
    new(
      workflow_run: workflow_run,
      triggered_by_retry: triggered_by_retry
    ).call
  end

  def call
    return if @workflow_run.nil?
    trigger_type
  end

  def initialize(
    workflow_run:,
    triggered_by_retry: false
  )
    @workflow_run = workflow_run
    @triggered_by_retry = triggered_by_retry
  end

  private

  def trigger
    @trigger ||= begin
      if trigger_ff?
        case @workflow_run.trigger_type
        when "Push"
          repositories_domain.pushes.by_id_and_repo_id(repository_id: @workflow_run.repository_id, id: @workflow_run.trigger_id)

        else
          @workflow_run.trigger
        end
      else
        @workflow_run.trigger
      end
    end
  end

  def original_trigger_type
    return @original_trigger_type if defined?(@original_trigger_type)

    if trigger_ff?
      if trigger.is_a? Issue
        @original_trigger_type = ISSUE
      elsif trigger.is_a? IssueComment
        @original_trigger_type = ISSUE_COMMENT
      elsif trigger.is_a? PullRequest
        @original_trigger_type = PULL_REQUEST
      elsif trigger && @workflow_run.trigger_type == "Push"
        @original_trigger_type = PUSH
      elsif trigger && @workflow_run.trigger_type == "Release"
        @original_trigger_type = RELEASE
      elsif trigger.is_a? Deployment
        @original_trigger_type = DEPLOYMENT
      elsif @workflow_run.event == "schedule"
        @original_trigger_type = SCHEDULE
      elsif @workflow_run.event == "repository_dispatch"
        @original_trigger_type = REPOSITORY_DISPATCH
      elsif @workflow_run.event == "workflow_dispatch"
        @original_trigger_type = WORKFLOW_DISPATCH
      elsif @workflow_run.event == "merge_group"
        @original_trigger_type = MERGE_GROUP
      else
        @original_trigger_type = OTHER
      end
    else
      if trigger.is_a? Issue
        @original_trigger_type = ISSUE
      elsif trigger.is_a? IssueComment
        @original_trigger_type = ISSUE_COMMENT
      elsif trigger.is_a? PullRequest
        @original_trigger_type = PULL_REQUEST
      elsif trigger.is_a? Push
        @original_trigger_type = PUSH
      elsif trigger.is_a? Release
        @original_trigger_type = RELEASE
      elsif trigger.is_a? Deployment
        @original_trigger_type = DEPLOYMENT
      elsif @workflow_run.event == "schedule"
        @original_trigger_type = SCHEDULE
      elsif @workflow_run.event == "repository_dispatch"
        @original_trigger_type = REPOSITORY_DISPATCH
      elsif @workflow_run.event == "workflow_dispatch"
        @original_trigger_type = WORKFLOW_DISPATCH
      elsif @workflow_run.event == "merge_group"
        @original_trigger_type = MERGE_GROUP
      else
        @original_trigger_type = OTHER
      end
    end
  end

  memoize def trigger_ff?
    GitHub.flipper[:workflow_trigger_push].enabled?
  end

  def trigger_type
    @triggered_by_retry ? RETRY : original_trigger_type
  end
end
