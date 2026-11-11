# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  class UsageReport
    class Error < StandardError; end
    class NoDataAvailableError < Error; end
    class TooManyRowsError < Error; end
    class InvalidDataFormatError < Error; end

    # Interface for Kusto client providers
    # Providers must implement: .kusto_client returning Kusto::Data::Client
    KustoClientProvider = T.type_alias { T.any(T.class_of(Azure::UsageReportsKustoClientProvider), T.class_of(Azure::SparkUsageReportsKustoClientProvider)) }

    sig { params(enterprise_id: T.nilable(Integer), organization_id: T.nilable(Integer), kusto_client_provider: KustoClientProvider).void }
    def initialize(enterprise_id: nil, organization_id: nil, kusto_client_provider: Azure::UsageReportsKustoClientProvider)
      if enterprise_id.nil? && organization_id.nil?
        raise ArgumentError, "Either enterprise_id or organization_id must be provided"
      end

      @enterprise_id = T.let(enterprise_id, T.nilable(Integer))
      @organization_id = T.let(organization_id, T.nilable(Integer))
      @enterprise = T.let(nil, T.nilable(Business))
      @organization = T.let(nil, T.nilable(Organization))
      @kusto_client_provider = T.let(kusto_client_provider, KustoClientProvider)

      if enterprise_id && organization_id && !enterprise_filter_enabled?
        raise ArgumentError, "Cannot provide both enterprise_id and organization_id"
      end
    end

    sig { params(date: T.nilable(Date), include_unknown_models: T::Boolean).returns(T::Array[T::Hash[String, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    def fetch(date: nil, include_unknown_models: false)
      if Rails.env.development?
        build_params = lambda do |date_value|
          if @organization_id
            { organization_id: @organization_id, date: date_value }
          else
            { enterprise_id: @enterprise_id, date: date_value }
          end
        end

        if EnterpriseReportImporter.imported_data_available?
          json_file = Pathname.new(EnterpriseReportImporter.imported_json_files.first)
          dataset = EnterpriseReportImporter.load_json_file_as_dataset(
            json_file,
            **build_params.call(date)
          )
        else
          inactive_days = ENV.fetch("COPILOT_METRICS_INACTIVE_DAYS", "0").to_i
          dataset = EnterpriseDailyFactory.generate_datatable_response(
            **build_params.call(date || Date.yesterday),
            inactive_days: inactive_days
          )
        end
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

      first_row = table.rows.first || []
      day_totals = first_row[day_totals_index.to_i] || []
      sorted_data = day_totals.sort_by { |daily_record| daily_record.dig("day") }

      unless include_unknown_models
        sorted_data = filter_unknown_models(sorted_data)
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
      date_value = first_row[day_totals_index.to_i]
      raise NoDataAvailableError, "No data available" if date_value.nil?
      Date.parse(date_value)

    rescue Date::Error
      raise InvalidDataFormatError, "Invalid data format"
    end

    private

    sig { returns(T.nilable(Business)) }
    def enterprise
      @enterprise ||= Business.find_by(id: @enterprise_id) if @enterprise_id
    end

    sig { returns(T.nilable(Organization)) }
    def organization
      @organization ||= Organization.find_by(id: @organization_id) if @organization_id
    end

    sig { params(data: T::Array[T::Hash[String, Object]]).returns(T::Array[T::Hash[String, Object]]) }
    def filter_unknown_models(data)
      data.map do |daily_record|
        daily_record.transform_values do |value|
          if value.is_a?(Array) && !value.empty? && value.first.is_a?(Hash)
            value.reject do |entry|
              (entry["model"] == EnterpriseDaily::Model::Unknown.serialize) ||
              (entry["feature"] == EnterpriseDaily::Feature::ChatPanelUnknownMode.serialize) ||
              (entry["language"] == EnterpriseDaily::UNKNOWN_LANGUAGE)
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
      KQL

      if enterprise_filter_enabled?
        if @enterprise_id
          base_query += <<~KQL
            | where enterprise_id == #{@enterprise_id}
          KQL
        end

        if @organization_id
          base_query += <<~KQL
            | where organization_id == #{@organization_id}
          KQL
        end
      else
        id_field = @organization_id ? "organization_id" : "enterprise_id"
        id_value = @organization_id || @enterprise_id

        base_query += <<~KQL
          | where #{id_field} == #{id_value}
        KQL
      end

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
      base_query = <<~KQL
        table("#{table_name}")
      KQL

      if enterprise_filter_enabled?
        if @enterprise_id
          base_query += <<~KQL
            | where enterprise_id == #{@enterprise_id}
          KQL
        end

        if @organization_id
          base_query += <<~KQL
            | where organization_id == #{@organization_id}
          KQL
        end
      else
        id_field = @organization_id ? "organization_id" : "enterprise_id"
        id_value = @organization_id || @enterprise_id

        base_query += <<~KQL
          | where #{id_field} == #{id_value}
        KQL
      end

      base_query + <<~KQL
        | sort by report_end_day, created_at desc
        | take 1
        | project report_end_day
      KQL
    end

    sig { returns(T::Boolean) }
    def enterprise_filter_enabled?
      entity = organization || enterprise
      return false unless entity

      FeatureFlag.vexi.enabled?("copilot_insights_org_query_enterprise_filter", entity, default: false)
    end

    sig { returns(Kusto::Data::Client) }
    def kusto_client
      @kusto_client_provider.kusto_client
    end

    sig { returns(String) }
    def database_name
      # copilot_insights_usage_report_blue_override is here because we can't selectively disable for an enterprise
      # This is used for staffshipping a blue cluster testing
      entity = enterprise || organization
      green_enabled = entity&.feature_flag_enabled?(:copilot_insights_usage_report_green_prefix, default: false)
      blue_override = entity&.feature_flag_enabled?(:copilot_insights_usage_report_blue_override, default: false)
      if green_enabled && !blue_override
        "green-cached-reports"
      else
        "blue-cached-reports"
      end
    end

    sig { returns(String) }
    def table_name
      @organization_id ? "organization_28_day_report_cached" : "enterprise_28_day_report_cached"
    end
  end
end
