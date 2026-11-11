# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Hydro consumer job for PullRequestCreate, PullRequestSynchronize, and
# PullRequestChangeBase events.
# Filters to DG-eligible PRs with One Pipeline enabled, then emits a
# `dependency_graph.pull_request_push` instrumenter event that the hydro
# subscription in dependency_graph.rb picks up and publishes as
# `github.dependencygraph.v1.PullRequestPush`.
#
# This mirrors HydroDependencyGraphPlatformOnPushJob for the PR flow.
class HydroDependencyGraphOnPullRequestJob < HydroMessageJob
  extend T::Helpers
  include GitHub::Memoizer

  retry_on_dirty_exit

  queue_as :hydro_dependency_graph_on_pull_request

  # Public: process a Hydro message for a PR create, synchronize, or change base event.
  sig { void }
  def perform
    return if repository_id.nil?
    return unless FeatureFlag.vexi.enabled?("dependency_graph_pull_request_push_consumer", repository, repository.owner, default: false)
    return unless dg_eligible_pr?
    return if fork_pr?

    instrument_dg_pull_request_push
  end

  private

  # Fork PRs are not supported for dependency graph snapshot processing.
  sig { returns(T::Boolean) }
  def fork_pr?
    !head_repository_id.nil? && head_repository_id != repository_id
  end

  # Checks whether this PR event is eligible for dependency graph processing.
  # Mirrors the push job's eligibility checks.
  #
  # NOTE: the One Pipeline gate (`dependency_graph_parse_once_diffs`) is checked
  # in the DS-API consumer rather than here, so we can roll out
  # `dependency_graph_pull_request_push_consumer` independently and measure
  # would-be-processed PR push volume via the consumer's
  # `dropped_event{reason=feature_flag_disabled}` metric before turning on diffs.
  sig { returns(T::Boolean) }
  def dg_eligible_pr?
    return false if GitHub.enterprise?
    return false unless GitHub.dependency_graph_enabled?
    return false unless repository.dependency_graph_enabled?
    return false if repository.owner&.spammy?

    true
  end

  sig { returns(Repository) }
  memoize def repository
    Repositories::Public.find_active!(T.must(repository_id))
  end

  # For PullRequestCreate, :repository is the base repo.
  # For PullRequestSynchronize, :base_repository is the base repo, :repository is the head repo.
  # For PullRequestChangeBase, :base_repository is the base repo.
  sig { returns(T.nilable(Integer)) }
  memoize def repository_id
    case schema
    when /PullRequestSynchronize/
      message.dig(:base_repository, :id) || message.dig(:repository, :id)
    else
      message.dig(:repository, :id) || message.dig(:base_repository, :id)
    end
  end

  sig { returns(T.nilable(Integer)) }
  memoize def pull_request_id
    message.dig(:pull_request, :id)
  end

  # For PullRequestCreate, :head_repository contains the head repo.
  # For PullRequestSynchronize, :repository is the head repo (fork pushes).
  sig { returns(T.nilable(Integer)) }
  memoize def head_repository_id
    case schema
    when /PullRequestSynchronize/
      message.dig(:repository, :id)
    else
      message.dig(:head_repository, :id)
    end
  end

  # Determines the trigger type from the hydro schema name.
  sig { returns(Symbol) }
  def trigger_type
    case schema
    when /PullRequestCreate/
      :CREATE
    when /PullRequestSynchronize/
      :SYNCHRONIZE
    when /PullRequestChangeBase/
      :CHANGE_BASE
    else
      :UNKNOWN
    end
  end

  sig { void }
  def instrument_dg_pull_request_push
    return if pull_request_id.nil?

    pr_data = message[:pull_request] || {}

    payload = {
      request_context: GitHub.context,
      repository: repository,
      owner: repository.owner,
      pull_request: {
        id: pull_request_id,
        head_sha: pr_data[:head_sha],
        base_sha: pr_data[:base_sha],
        head_branch: pr_data[:head_branch],
        base_branch: pr_data[:base_branch],
        draft: pr_data[:draft],
      },
      trigger_type: trigger_type,
      previous_ref_oid: message[:before_oid].presence || "",
      current_ref_oid: message[:after_oid].presence || pr_data[:head_sha] || "",
    }

    GlobalInstrumenter.instrument("dependency_graph.pull_request_push", payload)
  end
end
