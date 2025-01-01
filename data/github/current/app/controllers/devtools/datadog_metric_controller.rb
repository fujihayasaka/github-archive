# typed: true
# frozen_string_literal: true

class Devtools::DatadogMetricController < DevtoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required

  def index
    # Return 404 unless a feature flag is enabled
    return render_404 unless current_user.feature_enabled?(:devtools_datadog_metric_generator)
    render "devtools/datadog_metric/index"
  end

  def generate_datadog_metric # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user.feature_enabled?(:devtools_datadog_metric_generator)
    # Get the parameters from the form
    metric_type = params["metric-type"]
    metric_name = params["metric-name"]
    metric_value = params["metric-value"]
    metric_tags = params["tags"]

    # Validate metric name
    if metric_name.blank?
      return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric name. Must not be blank." }
    end

    # Validate with datadog metric name regex
    # Metric names must start with a letter.
    # Can only contain ASCII alphanumerics, underscores, and periods. Other characters are converted to underscores.
    # Should not exceed 200 characters (though less than 100 is generally preferred from a UI perspective)
    # Unicode is not supported.
    # It is recommended to avoid spaces.
    if metric_name !~ /\A[a-zA-Z0-9_\.]+\z/
      return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric name. See https://docs.datadoghq.com/developers/guide/what-best-practices-are-recommended-for-naming-metrics-and-tags/" }
    end

    # Iterate over the tags array and validate
    metric_tags.each do |metric_tag|
      # Validate tag is not blank
      next if metric_tag.blank?

      # Validate tag is in the format key:value
      # Tag keys must start with a letter and after that may contain the characters listed below:
      #   Alphanumerics
      #   Underscores
      #   Minuses
      #   Colons
      #   Periods
      #   Slashes
      if metric_tag !~ /\A[a-zA-Z][a-zA-Z0-9_\-\/\.]*:[a-zA-Z0-9_\-\/\.]*\z/
        return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid tag. Please see https://docs.datadoghq.com/getting_started/tagging/" }
      end
    end

    # Add datadodge metric tag
    metric_tags << "source:devtools-metric-generator"

    # Send the metric to Datadog based on the type
    case metric_type
    when "counter"
      # Validate metric value is an integer
      if metric_value.to_i.to_s != metric_value
        return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric value. Must be an integer." }
      end

      GitHub.dogstats.count(metric_name, metric_value.to_i, tags: metric_tags)

    when "distribution"
      # Validate metric value is a real number
      if metric_value.to_f.to_s != metric_value
        return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric value. Must be a number." }
      end

      GitHub.dogstats.distribution(metric_name, metric_value.to_f, tags: metric_tags)

    when "gauge"
      # Validate metric value is a real number
      if metric_value.to_f.to_s != metric_value
        return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric value. Must be a number." }
      end

      GitHub.dogstats.gauge(metric_name, metric_value.to_f, tags: metric_tags)

    when "histogram"
      # Validate metric value is a real number
      if metric_value.to_f.to_s != metric_value
        return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric value. Must be a number." }
      end

      GitHub.dogstats.histogram(metric_name, metric_value.to_f, tags: metric_tags)
    else
      return redirect_to devtools_datadog_metric_path, flash: { error: "Invalid metric type. Must be one of counter, distribution, gauge, histogram." }
    end

    redirect_to devtools_datadog_metric_path, notice: "Successfully generated the metric."
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?
    set_nav_breadcrumb ContextRegion::Devtools::DatadogMetricCrumb.new
  end
end
