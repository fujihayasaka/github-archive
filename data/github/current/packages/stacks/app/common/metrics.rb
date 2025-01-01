# typed: true
# frozen_string_literal: true

# FIXME: this name is extremely generic.
module Metrics

  INCREMENT = "increment"
  DECREMENT = "decrement"
  COUNT = "count"
  GAUGE = "gauge"
  TIMING = "timing"
  DISTRIBUTION = "distribution"
  HISTOGRAM = "histogram"

  def self.push_metric(metric_type, component, operation, metric, optional = {})
    metric_name = "stack_#{component}.#{operation}.#{metric}"

    if metric_type == INCREMENT || metric_type == DECREMENT
      if optional[:tags].nil?
        GitHub.dogstats.public_send(metric_type, metric_name)
      else
        GitHub.dogstats.public_send(metric_type, metric_name, tags: optional[:tags])
      end
    elsif metric_type == TIMING
      if optional[:tags].nil?
        GitHub.dogstats.timing(metric_name, (optional[:value] * 1000).round)
      else
        GitHub.dogstats.timing(metric_name, (optional[:value] * 1000).round, tags: optional[:tags])
      end
    else
      if optional[:tags].nil?
        GitHub.dogstats.public_send(metric_type, metric_name, optional[:value])
      else
        GitHub.dogstats.public_send(metric_type, metric_name, optional[:value], tags: optional[:tags])
      end
    end
  end
end
