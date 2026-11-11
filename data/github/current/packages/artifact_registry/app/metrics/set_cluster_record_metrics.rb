# typed: strict
# frozen_string_literal: true

class SetClusterRecordMetrics < SetClusterRecordMetricsBase
  sig { returns(Integer) }
  attr_reader :deployment_count

  sig { params(deployment_count: Integer).void }
  def initialize(deployment_count)
    @deployment_count = T.let(deployment_count, Integer)
    record_count_bucket = case deployment_count
    when 0..10 then "0-10"
    when 11..50 then "11-50"
    when 51..100 then "51-100"
    when 101..500 then "101-500"
    when 501..1000 then "501-1000"
    when 1001..3000 then "1001-3000"
    else "3000+"
    end

    set_metric_tags([
      "endpoint:set_cluster_deployment_records",
      "deployment_count_bucket:#{record_count_bucket}",
    ])
  end
end
