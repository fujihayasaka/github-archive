# typed: strict
# frozen_string_literal: true

class SetClusterRecordMetricsBase
  extend T::Helpers
  abstract!

  METRIC_PREFIX = T.let("artifacts_metadata.set_cluster_deployment_records", String)

  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :metric_tags

  sig { params(metric_name: String, metric_value: Numeric, tags: T::Array[String]).void }
  def publish_distribution_metric(metric_name, metric_value, tags = [])
    GitHub.dogstats.distribution(
      "#{METRIC_PREFIX}.#{metric_name}",
      metric_value,
      tags: T.must(metric_tags) + tags,
    )
  end

  protected

  sig { params(metric_tags: T::Array[String]).void }
  def set_metric_tags(metric_tags)
    @metric_tags = T.let(metric_tags, T.nilable(T::Array[String]))
  end
end
