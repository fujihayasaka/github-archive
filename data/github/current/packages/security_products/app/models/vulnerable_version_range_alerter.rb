# typed: true
# frozen_string_literal: true

# see tests for VulnerableVersionRangeCreateVulnerabilityAlerts
class VulnerableVersionRangeAlerter
  DATADOG_PREFIX = "vulnerable_version_range_alerter"
  EVENT_HYDRO_SCHEMA = "dependabot.v0.VulnerableDependencyFound"

  extend T::Sig
  include GitHub::DatadogHelper
  include GitHub::Memoizer

  sig { returns(VulnerableVersionRangeAlertingProcess) }
  attr_accessor :process

  sig { returns(VulnerabilityAlertingEvent) }
  attr_accessor :event

  sig { returns(VulnerableVersionRange) }
  attr_accessor :range

  sig { returns(T.nilable(String)) }
  attr_accessor :cursor

  attr_accessor :query

  sig { params(process: VulnerableVersionRangeAlertingProcess, cursor: T.nilable(String)).void }
  def initialize(process, cursor: nil)
    @process = process
    @event = T.let(T.must(process.vulnerability_alerting_event), VulnerabilityAlertingEvent)
    @range = T.let(T.must(process.vulnerable_version_range), VulnerableVersionRange)
    @cursor = cursor
    @query = fetch_dependents_from_range(range)
  end

  memoize def executed_query
    datadog_time(:query_time) do
      query.results # Executes the query and memoizes the result
    end

    query
  end

  # returns alertable_dependents so they can be counted in
  # VulnVersionRange#increment_total_alerts_processed_count
  sig { returns(T::Array[DependencyGraph::Dependent]) }
  def process_alertable_repos
    alertable_dependents = T.let([], T::Array[DependencyGraph::Dependent])
    datadog_time(:total_time) do
      dependents = executed_query.results.value!
      alertable_dependents =
        datadog_time(:filter_time) do
          filter_unalertable_repos(dependents)
        end

      datadog_histogram(
        dependent_count: dependents.count,
        alertable_dependent_count: alertable_dependents.count,
      )
      datadog_histogram(alertable_percentage: 100 * alertable_dependents.count / dependents.count) if dependents.any?

      datadog_time(:create_time) do
        publish_alert_creation_messages(range, alertable_dependents)
      end
    end
    alertable_dependents
  end

  sig { params(range: VulnerableVersionRange).returns(T.untyped) }
  def fetch_dependents_from_range(range)
    filter = {
      package_manager: range.ecosystem,
      package_name: range.affects,
      requirements: range.requirements,
      first: 100,
      preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled?,
    }
    filter[:after] = cursor if cursor

    backend = DependencyGraph::Client.new(timeout: 15, query_type: "all_repositories_with_version_range")

    DependencyGraph::AllRepositoriesWithVersionRangeQuery.new(
      dependents_filter: filter,
      backend: backend,
    )
  end

  # Not every dependent is reportable. Filter out dependents with
  # repos that have been archived or do not have alerts turned on.
  sig { params(dependents: T::Array[DependencyGraph::Dependent]).returns(T::Array[DependencyGraph::Dependent]) }
  def filter_unalertable_repos(dependents)
    # Filter out dependents with missing manifest paths
    dependents = dependents.select { |dep| dep.manifest_path.present? }

    grouped_dependents = dependents.group_by(&:repository_id)
    alertable_repo_ids = fetch_alertable_repo_ids(grouped_dependents.keys)

    T.unsafe(grouped_dependents).values_at(*alertable_repo_ids).flatten
  end

  sig { params(range: VulnerableVersionRange, alertable_dependents: T::Array[DependencyGraph::Dependent]).void }
  def publish_alert_creation_messages(range, alertable_dependents)
    message_count = 0

    alertable_dependents.filter_map do |dependent|
      datadog_time(:"alert.publish_time") do
        publish_message_to_hydro(range, dependent)
        message_count += 1
      end
    end
  ensure
    process.progress.increment_denominator(by: message_count.to_i) if message_count.to_i > 0
  end

  sig { params(range: VulnerableVersionRange, dependent: T.untyped).void }
  def publish_message_to_hydro(range, dependent)
    message = {
      repository_id: dependent.repository_id,
      vulnerable_dependency: {
        vulnerable_version_range_ids: [range.id],
        manifest_path: dependent.manifest_path,
        requirements: dependent.requirements,
        scope: dependent.scope,
      },
      vulnerability_alerting_event_id: event.id,
      vulnerable_version_range_alerting_process_id: process.id,
      created_at: Time.current
    }
    GitHub.hydro_publisher.publish(message, schema: EVENT_HYDRO_SCHEMA, partition_key: dependent.repository_id)
  end

  sig { returns(T::Boolean) }
  def more_to_process?
    !!executed_query.has_next? && next_cursor.present?
  end

  sig { returns(T.nilable(String)) }
  def next_cursor
    executed_query.dependent_end_cursor || executed_query.last_cursor
  end

  sig { returns(Integer) }
  def dependents_count
    executed_query.results.value!.size
  end

  private

  sig { params(repo_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def fetch_alertable_repo_ids(repo_ids)
    T.unsafe(Repository.where(id: repo_ids)).with_vulnerability_alerts_enabled.ids.to_set
  end
end
