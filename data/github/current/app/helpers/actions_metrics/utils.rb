# typed: true
# frozen_string_literal: true

module ActionsMetrics::Utils
  include ActionsUsageMetrics::Api::V1
  include ActionsMetrics::RepositoryResolver

  def get_projection_options(current_user, version)
    return nil unless !version.nil?

    projection_options = ActionsUsageMetrics::Api::V1::ProjectionOptions.new(version_override: version)
  end

  def map_minutes_to_ms(value)
    value * 60 * 1000
  end

  def map_runtime_from_enum(value)
    value_s = value&.to_s

    if value_s == "RUNNER_RUNTIME_LINUX"
      value_s = "linux"
    elsif value_s == "RUNNER_RUNTIME_MACOS"
      value_s = "macos"
    elsif value_s == "RUNNER_RUNTIME_WINDOWS"
      value_s = "windows"
    else
      value_s = "unknown"
    end

    value_s
  end

  def map_runner_from_enum(value)
    value_s = value&.to_s

    if value_s == "RUNNER_TYPE_HOSTED"
      value_s = "hosted"
    elsif value_s == "RUNNER_TYPE_HOSTED_LARGER"
      value_s = "hosted-larger"
    elsif value_s == "RUNNER_TYPE_SELF_HOSTED"
      value_s = "self-hosted"
    else
      value_s = "unknown"
    end

    value_s
  end

  def map_runtime_to_enum(value)
    value_s = value&.to_s

    if value_s == "linux"
      value_s = "RUNNER_RUNTIME_LINUX"
    elsif value_s == "macos"
      value_s = "RUNNER_RUNTIME_MACOS"
    elsif value_s == "windows"
      value_s = "RUNNER_RUNTIME_WINDOWS"
    else
      value_s = "RUNNER_RUNTIME_UNKNOWN"
    end

    value_s
  end

  def map_runner_to_enum(value)
    value_s = value&.to_s

    if value_s == "hosted"
      value_s = "RUNNER_TYPE_HOSTED"
    elsif value_s == "hosted-larger"
      value_s = "RUNNER_TYPE_HOSTED_LARGER"
    elsif value_s == "self-hosted"
      value_s = "RUNNER_TYPE_SELF_HOSTED"
    else
      value_s = "RUNNER_TYPE_UNKNOWN"
    end

    value_s
  end

  def process_results(items)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    unless items.nil?
      add_repo_info(items)

      items.each do |item|
        runner_type = item[:runner_type]

        unless runner_type.nil?
          item[:runner_type] = map_runner_from_enum(runner_type)
        end

        runtime = item[:runner_runtime]

        unless runtime.nil?
          item[:runner_runtime] = map_runtime_from_enum(runtime)
        end
      end
    end
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("process_results complete", {
      "code.namespace" => "ActionsMetrics::Utils",
      "code.function" => "process_results",
      "gh.actions_metrics.utils.process_results.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.utils.process_results.dist.time", elapsed_time)
  end

  def get_processed_filters(filters, org)
    array_copy = Array.new
    if filters&.is_a?(Array)
      filters.each do |item|
        item_copy = item.clone
        if item_copy[:key] == "repository"
          # map these values the repository ids
          item_copy[:key] = "repository_id"
          item_copy[:values] = Repository.where(name: item_copy[:values], owner_id: org.id).map { |repo| repo.id.to_s }.to_a
        elsif item[:key] == "runner_runtime"
          item_copy[:values] = item_copy[:values].map { |value| map_runtime_to_enum(value) }.to_a
        elsif item[:key] == "runner_type"
          item_copy[:values] = item_copy[:values].map { |value| map_runner_to_enum(value) }.to_a
        elsif item[:key] == "average_queue_minutes"
          item_copy[:key] = "average_queue_time"
          item_copy[:values] = item_copy[:values].map { |value| map_minutes_to_ms(value.to_f).to_s }.to_a
        elsif item[:key] == "average_run_minutes"
          item_copy[:key] = "average_run_time"
          item_copy[:values] = item_copy[:values].map { |value| map_minutes_to_ms(value.to_f).to_s }.to_a
        end


        array_copy.push(item_copy)
      end
    end

    array_copy
  end

end
