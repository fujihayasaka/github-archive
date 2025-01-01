# typed: strict
# frozen_string_literal: true

module Copilot::Metrics::Queries
  # This class is responsible for generating the Kusto query that will be used to fetch the direct data access reports
  # for an enterprise, within a date range.
  class DirectDataAccess

    sig { params(enterprise_id: Integer, since_date: T.nilable(Time), until_date: T.nilable(Time)).void }
    def initialize(enterprise_id:, since_date:, until_date:)
      @enterprise_id = T.let(enterprise_id, Integer)
      @since_date = T.let(since_date, T.nilable(Time))
      @until_date = T.let(until_date, T.nilable(Time))
    end

    sig { returns(String) }
    def get_reports
      table = <<~KQL
        DDE_ExecutedExports
      KQL
      common_filter = <<~KQL
          | extend has_activity = array_length(metadata) > 0
          | extend expanded_metadata = iff(has_activity, metadata, pack_array(bag_pack("Path", "")))
          | mv-expand singlemetadata = expanded_metadata
          | project business_id, business_name, target_date, export_date, uri = singlemetadata["Path"], has_activity
          | summarize uris = make_list_if(uri, uri != "") by business_id, business_name, target_date, export_date
          | order by target_date desc
      KQL

      table +
        for_business(@enterprise_id) +
        between_dates(since_date: @since_date, until_date: @until_date) +
        common_filter
    end

    private

    sig { params(enterprise_id: Integer).returns(String) }
    def for_business(enterprise_id)
      <<~KQL
        | where business_id == #{enterprise_id}
      KQL
    end

    sig { params(since_date: T.nilable(Time), until_date: T.nilable(Time)).returns(String) }
    def between_dates(since_date:, until_date:)
      if since_date && until_date
        <<~KQL
          | where target_date between (datetime('#{since_date.utc.iso8601}') .. datetime('#{until_date.utc.iso8601}'))
        KQL
      elsif since_date
        since_date(since_date)
      elsif until_date
        until_date(until_date)
      else
        since_date(Time.now.utc.beginning_of_day - 1.day)
      end
    end

    sig { params(since_date: T.nilable(Time)).returns(String) }
    def since_date(since_date)
      return "" if since_date.nil?

      formatted_date = since_date.utc.iso8601
      <<~KQL
        | where target_date >= datetime('#{formatted_date}')
      KQL
    end

    sig { params(until_date: T.nilable(Time)).returns(String) }
    def until_date(until_date)
      return "" if until_date.nil?

      formatted_date = until_date.utc.iso8601
      <<~KQL
        | where target_date <= datetime('#{formatted_date}')
      KQL
    end
  end
end
