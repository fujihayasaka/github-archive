# typed: true
# frozen_string_literal: true

class RepairDependabotAlertsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk
  retry_on_dirty_exit

  FILTERS = {
    "repository" => "repository_id",
    "vulnerability" => "vulnerability_id",
    "vulnerable_version_range" => "vulnerable_version_range_id",
  }.freeze

  reconcile "dependabot_alert",
    model_class: RepositoryVulnerabilityAlert,

    model_scope: ->(scope, job) { job.model_scope(scope) },
    elasticsearch_filters: ->(_, job) { job.elasticsearch_filters },

    prefills: [:searchable?],
    fields: %w[search_index_updated_at],
    accept: :searchable?,
    limit: 250

  sig { returns(Elastomer::RepairJob) }
  def repair!
    validate_repair_filter!
    super
  end

  sig { returns(String) }
  def group_key
    key = super
    return key unless repair_filter?

    # include the repair filter info in the group key to avoid collisions with other
    # repair jobs that may be running without a filter, or with a different filter
    key + "/#{repair_filter_key}=#{repair_filter_value}"
  end

  sig { void }
  def validate_repair_filter!
    return unless repair_filter?

    unless FILTERS.value?(repair_filter_key)
      raise ArgumentError, "Invalid repair filter key #{repair_filter_key}. " \
                           "Valid keys are: #{FILTERS.values.map(&:to_s).join(', ')}"
    end
  end

  sig { params(scope: T.untyped).returns(T.untyped) }
  def model_scope(scope)
    return scope unless repair_filter?

    # target alerts associated with the repair source
    scope.where(repair_filter_key => repair_filter_value)
  end

  sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
  def elasticsearch_filters
    return nil unless repair_filter?

    [{ term: { repair_filter_key => repair_filter_value } }]
  end

  sig { returns(T::Boolean) }
  def repair_filter?
    repair_filter_key.present? && repair_filter_value.present?
  end

  sig { returns(T.nilable(String)) }
  def repair_filter_key
    job_opts[:repair_filter_key]&.to_s
  end

  sig { returns(T.untyped) }
  def repair_filter_value
    job_opts[:repair_filter_value]
  end
end
