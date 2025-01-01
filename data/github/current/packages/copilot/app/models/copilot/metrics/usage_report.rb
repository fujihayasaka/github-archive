# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  class UsageReport
    class Error < StandardError; end
    class NoDataAvailableError < Error; end
    class TooManyRowsError < Error; end
    class InvalidDataFormatError < Error; end

    sig { params(enterprise_id: Integer).void }
    def initialize(enterprise_id:)
      @enterprise_id = T.let(enterprise_id, Integer)
      @enterprise = T.let(nil, T.nilable(Business))
    end

    sig { params(date: T.nilable(Date), include_unknown_models: T::Boolean).returns(T::Array[T::Hash[String, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def fetch(date: nil, include_unknown_models: false)
      if Rails.env.development?
        dataset = EnterpriseDailyFactory.generate_datatable_response(enterprise_id: @enterprise_id, date: date || Date.yesterday)
      else
        query = query(date: date)
        dataset = GitHub.dogstats.distribution_time("copilot.metrics.usage_report.kusto_query.duration", tags: { database: database_name, method: __method__ }) do
          kusto_client.query(database_name, query)
        end
      end

      table = dataset.primary_result_table
      day_totals_index = table.columns.find_index { |column| column.name == "day_totals" }

      raise NoDataAvailableError, "No data available" if table.rows.empty?
      raise TooManyRowsError, "Too many rows returned" if table.rows.size > 1
      raise InvalidDataFormatError, "Invalid data format" if day_totals_index.nil?

      first_row = table.rows.first
      day_totals = first_row[day_totals_index.to_i]
      sorted_data = day_totals.sort_by { |daily_record| daily_record.dig("day") }

      if enterprise&.feature_flag_enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
        unless include_unknown_models
          sorted_data = filter_unknown_models(sorted_data)
        end
      end

      sorted_data
    end

    sig { returns(Date) }
    def get_latest_date
      if Rails.env.development?
        return Date.yesterday
      else
        dataset = GitHub.dogstats.distribution_time("copilot.metrics.usage_report.kusto_query.duration", tags: { database: database_name, method: __method__ }) do
          kusto_client.query(database_name, latest_date_query)
        end
      end

      table = dataset.primary_result_table
      day_totals_index = table.columns.find_index { |column| column.name == "report_end_day" }

      raise NoDataAvailableError, "No data available" if table.rows.empty?
      raise TooManyRowsError, "Too many rows returned" if table.rows.size > 1
      raise InvalidDataFormatError, "Invalid data format" if day_totals_index.nil?

      first_row = table.rows.first
      Date.parse(first_row[day_totals_index.to_i])
    end

    sig { params(number_of_partitions: Integer, partition_number: Integer).returns(T::Array[{ business_id: Integer, latest_date: Date }]) }
    def self.get_latest_dates(number_of_partitions:, partition_number:)
      if Rails.env.development?
        businesses = Business.where("id % ? = ?", number_of_partitions, partition_number).pluck(:id)
        res = []
        businesses.each do |business_id|
          res << { business_id: business_id, latest_date: Date.yesterday }
        end
        res
      else
        dataset = GitHub.dogstats.distribution_time("copilot.metrics.usage_report.kusto_query.duration", tags: { database: database_name, method: __method__ }) do
          kusto_client.query(database_name, latest_dates_query(number_of_partitions: number_of_partitions, partition_number: partition_number))
        end

        table = dataset.primary_result_table
        business_id_index = table.columns.find_index { |column| column.name == "enterprise_id" }
        latest_date_index = table.columns.find_index { |column| column.name == "report_end_day" }

        raise NoDataAvailableError, "No data available" if table.rows.empty?

        res = []
        table.rows.each do |row|
          business_id = row[business_id_index.to_i]
          if business_id.nil? || business_id.to_s.empty?
            next
          end
          business_id = business_id.to_i
          latest_date = row[latest_date_index.to_i]
          if latest_date.nil? || latest_date.to_s.empty?
            next
          end
          latest_date = Date.parse(latest_date)
          res << { business_id: business_id, latest_date: latest_date }
        end
        res
      end
    end

    private

    sig { returns(T.nilable(Business)) }
    def enterprise
      @enterprise ||= Business.find_by(id: @enterprise_id)
    end

    sig { params(data: T::Array[T::Hash[String, Object]]).returns(T::Array[T::Hash[String, Object]]) }
    def filter_unknown_models(data)
      data.map do |daily_record|
        daily_record.transform_values do |value|
          if value.is_a?(Array) && !value.empty? && value.first.is_a?(Hash)
            value.reject do |entry|
              (entry["model"] == "unknown") ||
              (entry["feature"] == "chat_panel_unknown_mode") ||
              (entry["language"] == "unknown")
            end
          else
            value
          end
        end
      end
    end

    sig { params(date: T.nilable(Date)).returns(String) }
    def query(date: nil)
      base_query = <<~KQL
        table("#{table_name}")
        | where enterprise_id == #{@enterprise_id}
      KQL

      date_filter = if date
        <<~KQL
          | where report_end_day == "#{date.to_date.iso8601}"
        KQL
      else
        ""
      end

      sorting = <<~KQL
        | sort by report_end_day, created_at desc
      KQL

      limit = <<~KQL
        | take 1
      KQL

      base_query + date_filter + sorting + limit
    end

    sig { returns(String) }
    def latest_date_query
      <<~KQL
        table("#{table_name}")
        | where enterprise_id == #{@enterprise_id}
        | sort by report_end_day, created_at desc
        | take 1
        | project report_end_day
      KQL
    end

    sig { params(number_of_partitions: Integer, partition_number: Integer).returns(String) }
    def self.latest_dates_query(number_of_partitions:, partition_number:)
      <<~KQL
        table("#{table_name}")
        | where toint(enterprise_id) % #{number_of_partitions} == #{partition_number}
        | sort by report_end_day, created_at desc
        | summarize arg_max(report_end_day, report_end_day) by enterprise_id
        | project enterprise_id, report_end_day
      KQL
    end
    private_class_method :latest_dates_query

    sig { returns(Kusto::Data::Client) }
    def kusto_client
      Copilot::Metrics::Azure::UsageReportsKustoClientProvider.kusto_client
    end

    sig { returns(Kusto::Data::Client) }
    def self.kusto_client
      Copilot::Metrics::Azure::UsageReportsKustoClientProvider.kusto_client
    end
    private_class_method :kusto_client

    sig { returns(String) }
    def database_name
      # copilot_insights_usage_report_blue_override is here because we can't selectively disable for an enterprise
      # This is used for staffshipping a blue cluster testing
      green_enabled = enterprise&.feature_flag_enabled?(:copilot_insights_usage_report_green_prefix, default: false)
      blue_override = enterprise&.feature_flag_enabled?(:copilot_insights_usage_report_blue_override, default: false)
      if green_enabled && !blue_override
        "green-cached-reports"
      else
        "blue-cached-reports"
      end
    end

    sig { returns(String) }
    def self.database_name
      if FeatureFlag.vexi.enabled?(:copilot_insights_usage_report_green_prefix, default: false)
        "green-cached-reports"
      else
        "blue-cached-reports"
      end
    end
    private_class_method :database_name

    sig { returns(String) }
    def table_name
      "enterprise_28_day_report_cached"
    end

    sig { returns(String) }
    def self.table_name
      "enterprise_28_day_report_cached"
    end
    private_class_method :table_name
  end
end
