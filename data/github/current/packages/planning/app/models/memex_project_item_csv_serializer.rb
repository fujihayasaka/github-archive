# typed: true
# frozen_string_literal: true

class MemexProjectItemCsvSerializer
  include GitHub::Tracing

  UNEXPECTED_REDACTION_LOG_MESSAGE = "A project item was redacted by the legacy item redactor rather than the Elasticsearch query redactor",
  UNEXPECTED_REDACTION_METRIC = "memex_project_item_csv_serializer.unexpected_legacy_redactions"
  ZERO_REDACTIONS_METRIC = "memex_project_item_csv_serializer.zero_legacy_redactions"

  trace_method(
    :csv_serialized_memex_items,
    span_annotator: ->(serializer, span, _context, result) do
      span.add_attributes(
        {
          "gh.memex.csv_serializer.height" => result.length,
          "gh.memex.csv_serializer.height_bucket" => MemexPerformanceStatsHelper.height_bucket(result.length),
          "gh.memex.csv_serializer.width" => serializer.columns.length,
          "gh.memex.csv_serializer.width_bucket" => MemexPerformanceStatsHelper.width_bucket(serializer.columns.length),
          "gh.memex.csv_serializer.has_prefilled_associations" => serializer.prefilled_associations.present?,
        }.merge(MemexPerformanceStatsHelper.column_count_by_type(serializer.columns))
      )
    end
  )

  attr_reader :viewer, :memex, :columns, :prefilled_associations

  class Result
    attr_reader :csv_headers, :csv_rows

    def initialize(csv_headers:, csv_rows:)
      @csv_headers = csv_headers
      @csv_rows = csv_rows
    end

    def entries
      return @csv_entries if defined?(@csv_entries)
      @csv_entries = [csv_headers, *csv_rows]
    end
  end

  def initialize(viewer:, memex:, items:, prefilled_associations: nil, columns: nil, cap_filter: nil, query_redactor_results: nil)
    @viewer = viewer
    @memex = memex
    @columns = T.let(columns.nil? ? memex.default_view&.visible_columns : Array.wrap(columns), T.nilable(T::Array[MemexProjectColumn]))
    @prefilled_associations = prefilled_associations
    @redactor = T.let(MemexProjectItemRedactor.new(
      viewer:,
      items:,
      columns: @columns,
      prefilled_associations: @prefilled_associations,
      cap_filter:,
      query_redactor_results:
    ), MemexProjectItemRedactor)
  end

  def result
    return @result if defined?(@result)

    @result = Result.new(
      csv_headers:,
      csv_rows: csv_serialized_memex_items
    )
  end

  private

  def csv_headers
    return @csv_headers if defined?(@csv_headers)

    @csv_headers = @columns&.map(&:name)
    @csv_headers.insert(
      MemexProjectColumn::CSV_DEFAULT_COLUMN[:index],
      MemexProjectColumn::CSV_DEFAULT_COLUMN[:header]
    ) if @csv_headers.present?
    @csv_headers&.to_csv || ""
  end

  def csv_serialized_memex_items
    return @csv_serialized_memex_items if defined?(@csv_serialized_memex_items)

    @csv_serialized_memex_items = redacted_items&.map do |item|
      item.to_csv(
        columns: @columns,
        prefilled_associations: @prefilled_associations,
        redacted_issue_ids:
      )
    end
  end

  def redacted_items
    return @redacted_items if defined?(@redacted_items)

    @redacted_items = @redactor.items
    log_redactions!

    @redacted_items
  end

  def redacted_issue_ids
    return @redacted_issue_ids if defined?(@redacted_issue_ids)
    @redacted_issue_ids = @redactor.redacted_issue_ids
  end

  def log_redactions!
    return unless @redacted_items.present?

    redactions_count = 0
    @redacted_items.each do |item|
      next unless item.redacted_item_type?

      GitHub.logger.info(
        UNEXPECTED_REDACTION_LOG_MESSAGE,
        {
          "code.namespace" => self.class.name,
          "code.function" => "result",
          "gh.memex_project.id" => @memex.id,
          "gh.memex_project_item.id" => item.id,
          "gh.user.id" => @viewer&.id
        }
      )
      redactions_count += 1
    end

    GitHub.dogstats.count(UNEXPECTED_REDACTION_METRIC, redactions_count)
    GitHub.dogstats.increment(ZERO_REDACTIONS_METRIC) if redactions_count == 0

    nil
  end
end
