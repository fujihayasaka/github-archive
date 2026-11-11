# typed: strict
# frozen_string_literal: true

class SetClusterBackgroundJobMetrics < SetClusterRecordMetricsBase
  sig { returns(String) }
  attr_reader :job_name

  sig { params(job_name: String).void }
  def initialize(job_name)
    @job_name = T.let(job_name, String)

    set_metric_tags([
      "endpoint:set_cluster_deployment_records",
      "job_name:#{job_name}",
    ])
  end
end
