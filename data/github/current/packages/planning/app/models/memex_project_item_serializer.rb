# typed: true
# frozen_string_literal: true

class MemexProjectItemSerializer
  include GitHub::Tracing
  include FeatureFlagHelper

  UNEXPECTED_REDACTION_LOG_MESSAGE = "A project item was redacted by the legacy item redactor rather than the Elasticsearch query redactor",
  UNEXPECTED_REDACTION_METRIC = "memex_project_item_serializer.unexpected_legacy_redactions"
  ZERO_REDACTIONS_METRIC = "memex_project_item_serializer.zero_legacy_redactions"

  trace_method(
    :serialized_memex_items,
    span_annotator: ->(serializer, span, _context, result) do
      span.add_attributes(
        {
          "gh.memex.serializer.height" => result.length,
          "gh.memex.serializer.height_bucket" => MemexPerformanceStatsHelper.height_bucket(result.length),
          "gh.memex.serializer.width" => serializer.columns.length,
          "gh.memex.serializer.width_bucket" => MemexPerformanceStatsHelper.width_bucket(serializer.columns.length),
          "gh.memex.serializer.has_prefilled_associations" => serializer.prefilled_associations.present?,
        }.merge(MemexPerformanceStatsHelper.column_count_by_type(serializer.columns))
      )
    end
  )

  attr_reader :viewer, :memex, :columns, :prefilled_associations

  class Result
    attr_reader :items

    def initialize(items:)
      @items = items
    end
  end

  def initialize(viewer:, memex:, items:, prefilled_associations: nil, columns: nil, cap_filter: nil, from_paginated_context: false, query_redactor_results: nil)
    @viewer = viewer
    @memex = memex
    @columns = columns.nil? ? memex.default_view.visible_columns : columns
    @prefilled_associations = prefilled_associations
    @redactor = MemexProjectItemRedactor.new(
      viewer: viewer,
      items: items,
      columns: @columns,
      prefilled_associations: @prefilled_associations,
      cap_filter: cap_filter,
      query_redactor_results: query_redactor_results
    )
    @from_paginated_context = from_paginated_context
  end

  def result
    return @result if defined?(@result)
    @result = Result.new(items: serialized_memex_items)
  end

  private

  def redacted_items
    return @redacted_items if defined?(@redacted_items)

    @redacted_items = @redactor.items
    log_redactions! if @from_paginated_context

    @redacted_items
  end

  def redacted_issue_ids
    return @redacted_issue_ids if defined?(@redacted_issue_ids)
    @redacted_issue_ids = @redactor.redacted_issue_ids
  end

  def serialized_memex_items
    return @serialized_memex_items if defined?(@serialized_memex_items)

    @serialized_memex_items = redacted_items.map do |item|
      item.to_hash(
        columns: @columns,
        prefilled_associations: @prefilled_associations,
        redacted_issue_ids: redacted_issue_ids
      )
    end
  end

  private def log_redactions!
    num_redactions = 0

    @redacted_items.each do |item|
      next unless item.redacted_item_type?

      GitHub.logger.info(
        UNEXPECTED_REDACTION_LOG_MESSAGE,
        {
          "code.namespace" => self.class.name,
          "code.function" => "result",
          "gh.memex.project.id" => memex.id,
          "gh.memex.item.id" => item.id,
          "gh.user.id" => viewer&.id
        }
      )

      num_redactions += 1
    end

    GitHub.dogstats.count(UNEXPECTED_REDACTION_METRIC, num_redactions)
    GitHub.dogstats.increment(ZERO_REDACTIONS_METRIC) if num_redactions == 0

    nil
  end
end
