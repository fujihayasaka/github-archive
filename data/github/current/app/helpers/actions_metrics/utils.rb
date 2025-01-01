# typed: true
# frozen_string_literal: true

module ActionsMetrics::Utils
  include ActionsUsageMetrics::Api::V1
  include ActionsMetrics::RepositoryResolver
  include ActionsMetrics::OrgResolver

  def get_projection_options(current_user, version)
    return nil if version.nil?

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
      add_org_info(items)

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

  def get_processed_filters(filters, biz, org, text_filter_real_column)
    array_copy = Array.new

    if filters&.is_a?(Array)
      filters.each do |item|
        item_copy = item.clone
        if item_copy[:key] == "repository"
          # map these values the repository ids
          item_copy[:values] = nil
          item_copy[:key] = "repository_id"
          if !org.nil?
            # repo filtering only at org level
            item_copy[:values] = org.repositories.where(name: item[:values]).map { |repo| repo.id.to_s }.to_a
          end
        elsif item_copy[:key] == "org"
          # map these values the org ids
          item_copy[:values] = nil
          item_copy[:key] = "owner_id"
          if !biz.nil?
            # org filtering only at enterprise level
            item_copy[:values] = biz.organizations.where(display_login: item[:values]).map { |org| org.id.to_s }.to_a
          end
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
        elsif item[:key] == "text"
          # we need to treat text filters as a special case because their behavior changes per tab
          # - on workflows or jobs tab (actual text fields) treat them like a regular contains filter checking against the column text
          # - on repos or orgs tab we need to get matching orgs/repos and then combine them with other filters of same type

          item_copy[:key] = text_filter_real_column

          if text_filter_real_column == "org"
            # find matching orgs and then combine filter with other filters of same type
            if !biz.nil? && !item[:values].nil? && !item[:values][0].nil? # text filters only have 1 value
              # org filtering only at enterprise level
              item_copy[:key] = "owner_id"
              item_copy[:values] = biz.organizations.where("display_login like ?", "%#{item[:values][0]}%").map { |org| org.id.to_s }.to_a
              item_copy[:operator] = "FILTER_OPERATOR_EQUALS" # the "contains" portion is executed here, so in service this should be exact match
            end
          elsif text_filter_real_column == "repository"
            # find matching repos and then combine filter with other filters of same type
            if !org.nil? && !item[:values].nil? && !item[:values][0].nil? # text filters only have 1 value
              # repo filtering only at org level
              item_copy[:key] = "repository_id"
              item_copy[:values] = org.repositories.where("name like ?", "%#{item[:values][0]}%").map { |repo| repo.id.to_s }.to_a
              item_copy[:operator] = "FILTER_OPERATOR_EQUALS" # the "contains" portion is executed here, so in service this should be exact match
            end
            # else this is a regular text comparison and we don't need to do anything else
          end
        end

        if !item_copy[:values].nil? && item_copy[:values].length > 0
          # before pushing this filter into array check if any duplicates
          # - this only needs to be done for FILTER_OPERATOR_EQUALS because it is only possible through certain text filters

          duplicate_filter = array_copy.find { |f| f[:key] == item_copy[:key] && f[:operator] == "FILTER_OPERATOR_EQUALS" }

          if !duplicate_filter.nil?
            duplicate_filter[:values] = duplicate_filter[:values] + item_copy[:values] # combine filter values into existing filter
            item_copy[:values] = nil # set current filter values to nil so they are ignored (already added to duplicate)
          end
        end

        array_copy.push(item_copy) if !item_copy[:values].nil? && item_copy[:values].length > 0
      end
    end

    array_copy
  end

end
