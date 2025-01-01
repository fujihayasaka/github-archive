# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class Query

    sig { returns(String) }
    attr_reader :tabular_input

    sig { returns(T::Array[BaseFilter]) }
    attr_reader :filters

    sig { returns(T::Array[SummaryField]) }
    attr_reader :summary_fields

    sig { returns(T::Array[SummaryKeyField]) }
    attr_reader :summary_key_fields

    sig { returns(T.nilable(TimestampIncrementSummaryKey)) }
    attr_accessor :timestamp_increment_summary_key

    sig { returns(T::Array[BaseFilter]) }
    attr_reader :summary_filters

    sig { returns(T::Array[SortDefinition]) }
    attr_reader :sort_definitions

    sig { returns(T.nilable(Pager)) }
    attr_accessor :pager

    sig { params(tabular_input: String).void }
    def initialize(tabular_input)
      raise "tabular_input cannot be empty" if tabular_input.empty?

      @tabular_input = tabular_input
      @filters = T.let([], T::Array[BaseFilter])
      @summary_fields = T.let([], T::Array[SummaryField])
      @summary_key_fields = T.let([], T::Array[SummaryKeyField])
      @summary_filters = T.let([], T::Array[BaseFilter])
      @sort_definitions = T.let([], T::Array[SortDefinition])
    end

    # Returns the Kusto query text.
    sig { returns(String) }
    def text
      # Ensure required parameters are populated.
      raise Error.new(ErrorCode::FILTERS_NOT_SPECIFIED) if @filters.empty?
      raise Error.new(ErrorCode::SUMMARY_FIELDS_NOT_SPECIFIED) if @summary_fields.empty?
      raise Error.new(ErrorCode::SORT_DEFINITIONS_NOT_SPECIFIED_WHEN_PAGING) if @sort_definitions.empty? && @pager
      missing_tenant_id = GitHub.multi_tenant_enterprise? && !@filters.any? { |f| f.field == FilterField::TenantId }
      raise "Current tenant is not set and is required in multi-tenant mode" if missing_tenant_id

      value = String.new

      value << <<~KQL if @pager
        let results = materialize(
        KQL

      value << <<~KQL
        #{@tabular_input}
        | where
        #{@filters.map { |c| "    #{c}" }.join(" and\n")}
        | summarize
        #{@summary_fields.map { |a| "    #{a}" }.join(",\n")}
        KQL

      value << <<~KQL if has_summary_keys?
            by
        #{get_summary_keys.map { |k| "    #{k}" }.join(",\n")}
        KQL

      value << <<~KQL unless @summary_filters.empty?
        | where
        #{@summary_filters.map { |c| "    #{c}" }.join(" and\n")}
        KQL

      value << <<~KQL if @sort_definitions.any?
        | sort by
        #{@sort_definitions.map { |s| "    #{s}" }.join(",\n")}
        KQL

      value << <<~KQL if @pager
        );
        results | where #{@pager};
        results | count
        KQL

      value
    end

    # Returns a hash of parameters to be passed to the Kusto query.
    sig { returns(T::Hash[String, T.untyped]) }
    def parameters
      merged_parameters = T.let({}, T::Hash[String, T.untyped])
      merged_parameters = merged_parameters.merge(@filters.map(&:parameters).reduce({}, &:merge))
      merged_parameters = merged_parameters.merge(@summary_filters.map(&:parameters).reduce({}, &:merge))
      merged_parameters = merged_parameters.merge(@timestamp_increment_summary_key.parameters) if @timestamp_increment_summary_key
      merged_parameters = merged_parameters.merge(@pager.parameters) if @pager
      merged_parameters
    end

    private

    sig { returns(T::Boolean) }
    def has_summary_keys?
      @summary_key_fields.any? || !!@timestamp_increment_summary_key
    end

    sig { returns(T::Array[T.untyped]) }
    def get_summary_keys
      @summary_key_fields + [@timestamp_increment_summary_key].compact
    end
  end
end
