# typed: strict
# frozen_string_literal: true

class MergeQueues::MergeGroupComponent < ApplicationComponent

  IN_PROGRESS_STATES  = T.let(%w(pending in_progress queued), T::Array[String])
  UNSUCCESSFUL_STATES = T.let(%w(failure errored), T::Array[String])

  # These are fairly specific to GitHub's setup but could be perhaps made more generic for customers if we ever end
  # up having a good way of differentating this in the deployment API.
  PRODUCTION_DEPLOY_ENVIRONMENT = "production"
  CANARY_DEPLOY_ENVIRONMENT     = "production/canary"

  class DeploymentSummaryStatus < T::Enum
    enums do
      InProgress = new(:in_progress)
      Success = new(:success)
      Unsuccessful = new(:unsuccessful)
    end
  end

  sig do
    params(
      merge_queue: T.nilable(MergeQueue),
      repository: T.nilable(Repository),
      merge_group: T.nilable(MergeQueues::Group[MergeQueueEntry]),
    ).void
  end
  def initialize(merge_queue:, repository:, merge_group:)
    @merge_queue = merge_queue
    @repository = repository
    @merge_group = merge_group
  end

  sig { returns(T.nilable(String)) }
  memoize def head_oid
    entries.last&.head_sha
  end

  private

  sig { returns(Repository) }
  def repository
    T.must(@repository)
  end

  sig { returns(MergeQueue) }
  memoize def merge_queue
    T.must(@merge_queue)
  end

  sig { returns(MergeQueues::Group[MergeQueueEntry]) }
  memoize def merge_group
    T.must(@merge_group)
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless @merge_queue && @repository && @merge_group
    return false unless GitHub.merge_queues_enabled?
    return false unless repository.merge_queue_enabled?
    return false if @merge_group.empty?

    merge_queue.requires_deployments_before_merging?
  end

  sig { returns(T::Array[MergeQueueEntry]) }
  memoize def entries
    merge_group.entries
  end

  # the last entry is special because it's the one we use to get the status
  # for the entire merge group.
  sig { returns(T.nilable(MergeQueueEntry)) }
  memoize def last_entry
    entries.last
  end

  sig { returns(T::Boolean) }
  memoize def solo?
    merge_group.solo?
  end

  sig { returns(T::Boolean) }
  def locked?
    merge_group.locked?
  end

  sig { returns(T::Boolean) }
  memoize def waiting_on_deployments?
    locked?
  end

  sig { returns(String) }
  def merge_status_description
    case group_state = merge_group.state
    when MergeQueues::Group::State::Empty,
      MergeQueues::Group::State::MinimumSizeNotMet
      "Minimum group size not met, waiting for more entries."
    when MergeQueues::Group::State::Mergeable
      last_entry_status_description
    else
      T.absurd(group_state)
    end
  end

  sig { returns(String) }
  def last_entry_status_description
    return locked_status_description if last_entry&.locked?

    entry_state = last_entry&.entry_state
    if entry_state == MergeQueues::Entry::State::AwaitingChecks
      "Checks are pending."
    elsif entry_state == MergeQueues::Entry::State::Mergeable
      "Waiting on merge group to be locked."
    elsif entry_state == MergeQueues::Entry::State::Unmergeable
      # NOTE: The grouping algorithm should never result in a group in this state.
      "Cannot be merged."
    elsif entry_state == MergeQueues::Entry::State::Waiting || entry_state == MergeQueues::Entry::State::Queued
      # NOTE: The grouping algorithm should never result in a group in this state.
      "In the queue."
    else
      "Unknown state."
    end
  end

  sig { returns(String) }
  def locked_status_description
    if waiting_on_deployments?
      environments = deployment_environments_needed_to_merge

      message =  "Waiting on deployment"
      message += " to #{environments.sort.to_sentence}" if environments.any?
      message +  "."
    else
      "All checks passing, no conflict with #{merge_queue.branch}."
    end
  end

  sig { returns(T::Array[String]) }
  memoize def deployment_environments_needed_to_merge
    environments = Deployment
      .current_deployments_for_merge_queue(merge_queue)
      .active
      .pluck(:environment)
      .to_set

    merge_queue
      .required_deployment_environments
      .reject { environments.include?(_1) }
  end

  sig { returns(T.nilable(DeployInstructions)) }
  memoize def deploy_instructions
    instructions = DeployInstructions.new(repository:)
    if instructions.has_instructions_file?
      instructions
    end
  end

  sig { returns(T::Boolean) }
  def show_deployment_progress?
    any_production_deployments? && any_canary_deployments?
  end

  sig { returns(Integer) }
  def percent_audience_served
    return 0 unless any_production_deployments?

    if successful_production_deploy?
      100
    elsif successful_canary_deploy? || failed_production_deploy?
      10
    else
      0
    end
  end

  sig { returns(String) }
  def deployment_summary
    if any_canary_deployments?
      canary_deployment_summary
    else
      generic_deployment_summary
    end
  end

  sig { returns(String) }
  def canary_deployment_summary
    if successful_production_deploy?
      "Deployed to production"
    elsif successful_canary_deploy?
      "Deployed to canary"
    else
      generic_deployment_summary
    end
  end

  sig { returns(String) }
  def generic_deployment_summary
    case status = latest_deployment_summary_status
    when DeploymentSummaryStatus::Success
      "Deployed to #{latest_deployment_environment}"
    when DeploymentSummaryStatus::InProgress
      "Deploying to #{latest_deployment_environment}..."
    when DeploymentSummaryStatus::Unsuccessful
      "Failed deployment to #{latest_deployment_environment}"
    else
      T.absurd(status)
    end
  end

  sig { returns(T.nilable(String)) }
  def log_url
    latest_deployment&.log_url
  end

  sig { returns(String) }
  def deployment_progress_color
    if successful_production_deploy?
      "color-bg-success-emphasis"
    elsif successful_canary_deploy?
      "color-bg-accent-emphasis"
    else
      "color-bg-subtle"
    end
  end

  sig { returns(Symbol) }
  def deployment_status_icon_color
    return :danger if latest_deployment_failed?

    pending_colour = :attention
    ready_colour = :success

    if any_canary_deployments?
      if successful_production_deploy? || successful_canary_deploy?
        return ready_colour
      else
        return pending_colour
      end
    end

    if latest_deployment_in_progress?
      pending_colour
    else
      ready_colour
    end
  end

  sig { returns(T::Boolean) }
  def latest_deployment_canary?
    latest_deployment&.environment == CANARY_DEPLOY_ENVIRONMENT
  end

  sig { returns(T::Boolean) }
  def latest_deployment_production?
    latest_deployment&.environment == PRODUCTION_DEPLOY_ENVIRONMENT
  end

  sig { returns(T::Boolean) }
  def latest_deployment_successful?
    latest_deployment_summary_status == DeploymentSummaryStatus::Success
  end

  sig { returns(T::Boolean) }
  def latest_deployment_in_progress?
    latest_deployment_summary_status == DeploymentSummaryStatus::InProgress
  end

  sig { returns(T::Boolean) }
  def latest_deployment_failed?
    latest_deployment_summary_status == DeploymentSummaryStatus::Unsuccessful
  end

  sig { returns(T::Boolean) }
  def successful_production_deploy?
    latest_deployment_production? && latest_deployment_successful?
  end

  sig { returns(T::Boolean) }
  def successful_canary_deploy?
    (latest_deployment_production? && latest_deployment_in_progress?) ||
      (latest_deployment_canary? && latest_deployment_successful?)
  end

  sig { returns(T::Boolean) }
  def failed_production_deploy?
    latest_deployment_production? && latest_deployment_failed?
  end

  sig { returns(T.nilable(Deployment)) }
  memoize def latest_deployment
    merge_queue.active_deployments.first
  end

  sig { returns(T::Boolean) }
  def any_production_deployments?
    # Make use of cached latest_deployment
    latest_deployment.present?
  end

  sig { returns(T::Boolean) }
  memoize def any_canary_deployments?
    # Make use of cached latest_deployment if we have it and it happens to be canary.
    latest_deployment_canary? ||
      # Otherwise, check if we've ever had any canary deployments for this repository.
      repository.deployments.where(environment: "production/canary").any?
  end

  sig { returns(T.nilable(String)) }
  def latest_deployment_environment
    return "canary" if latest_deployment_canary?

    latest_deployment&.environment
  end

  sig { returns(DeploymentSummaryStatus) }
  memoize def latest_deployment_summary_status
    if UNSUCCESSFUL_STATES.include?(latest_deployment&.state)
      DeploymentSummaryStatus::Unsuccessful
    elsif IN_PROGRESS_STATES.include?(latest_deployment&.state)
      DeploymentSummaryStatus::InProgress
    else
      DeploymentSummaryStatus::Success
    end
  end
end
