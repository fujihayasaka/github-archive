# typed: true
# frozen_string_literal: true

module Validators
  class MemexProjectChartConfigurationValidator < ActiveModel::EachValidator
    # `record` is the MemexProjectChart record
    # `attribute` is the attribute being validated i.e. :configuration
    # `value` is the value of the `configuration` attribute that we want to run our validations against
    def validate_each(record, attribute, value)
      return unless value
      ValidationTarget.new(record:, attribute:, value:).validate
    end

    class ValidationTarget
      DATE_REGEX = /\d{4}-\d{2}-\d{2}/
      JSON_BYTESIZE_LIMIT = 4096

      def initialize(record:, attribute:, value:)
        @record = record
        @attribute = attribute
        @value = value
      end

      def validate
        validate_is_within_bytesize_limit
        validate_filter
        validate_type
        validate_x_axis
        validate_y_axis
        validate_time
      end

      private

      attr_reader :record, :attribute, :value

      def validate_is_within_bytesize_limit
        if value.to_json.bytesize > JSON_BYTESIZE_LIMIT
          record.errors.add(attribute, "must be fewer than #{JSON_BYTESIZE_LIMIT} bytes as JSON")
        end
      end

      def validate_filter
        unless value["filter"]
          record.errors.add(attribute, "'filter' must be present")
          return
        end
        unless value["filter"].is_a?(String)
          record.errors.add(attribute, "'filter' must be a string")
          return
        end
        unless value["filter"].length < MemexProjectView::FILTER_CHARACTERS_LIMIT
          record.errors.add(
            attribute,
            "'filter' length must be fewer than #{MemexProjectView::FILTER_CHARACTERS_LIMIT} characters"
          )
        end
      end

      def validate_type
        unless value["type"]
          record.errors.add(attribute, "'type' must be present")
          return
        end
        unless MemexProjectChart::CHART_TYPES.include?(value["type"])
          record.errors.add(
            attribute,
            "'type' must be one of: #{MemexProjectChart::CHART_TYPES.join(", ")}"
          )
        end
      end

      def validate_x_axis
        validate_is_a_hash(field: value["xAxis"], field_name: "xAxis")
        return unless value["xAxis"]&.is_a?(Hash)
        validate_data_source
        validate_group_by
      end

      def validate_data_source
        data_source = value["xAxis"]["dataSource"]
        validate_is_a_hash(field: data_source, field_name: "xAxis.dataSource")
        return unless data_source&.is_a?(Hash)

        column = data_source["column"]
        unless column && (column == "time" || column.is_a?(Integer))
          record.errors.add(
            attribute,
            "'xAxis.dataSource.column' must be 'time' or an integer"
          )
        end

        validate_time_defaults(data_source_column: column)
        validate_sort_order(sort_order: data_source["sortOrder"], field_name: "xAxis.dataSource.sortOrder")
      end

      def validate_is_a_hash(field:, field_name:)
        unless field
          record.errors.add(attribute, "'#{field_name}' must be present")
          return
        end

        unless field.is_a?(Hash)
          record.errors.add(attribute, "'#{field_name}' must be a hash")
        end
      end

      def validate_time_defaults(data_source_column:)
        time = value["time"]
        # Ignore time fields if not a historical chart
        unless data_source_column == "time"
          value.delete("time")
          return
        end
        # Add default time period if not present
        unless time
          value["time"] = { "period" => MemexProjectChart::DEFAULT_PERIOD }
          nil
        end
      end

      def validate_sort_order(sort_order:, field_name:)
        return unless sort_order
        unless MemexProjectChart::SORT_ORDERS.include?(sort_order)
          record.errors.add(
            attribute,
            "'#{field_name}' must be one of: #{MemexProjectChart::SORT_ORDERS.join(", ")}"
          )
        end
      end

      def validate_group_by
        group_by = value["xAxis"]["groupBy"]
        # group_by is not required but if it is present it has to be a hash
        if group_by
          validate_is_a_hash(field: group_by, field_name: "xAxis.groupBy")
        end
        # if group_by is not present or not a hash, bail out here
        return unless group_by&.is_a?(Hash)

        column = group_by["column"]
        unless column&.is_a?(Integer)
          record.errors.add(
            attribute,
            "'xAxis.groupBy.column' must be an integer"
          )
        end
        validate_sort_order(sort_order: group_by["sortOrder"], field_name: "xAxis.groupBy.sortOrder")
      end

      def validate_y_axis
        validate_is_a_hash(field: value["yAxis"], field_name: "yAxis")
        return unless value["yAxis"]&.is_a?(Hash)

        validate_aggregate
      end

      def validate_aggregate
        aggregate = value["yAxis"]["aggregate"]
        validate_is_a_hash(field: aggregate, field_name: "yAxis.aggregate")
        return unless aggregate&.is_a?(Hash)

        validate_operation(operation: aggregate["operation"], field_name: "yAxis.aggregate.operation")
        validate_columns_array(columns: aggregate["columns"], field_name: "yAxis.aggregate.columns")
        validate_sort_order(sort_order: aggregate["sortOrder"], field_name: "yAxis.aggregate.sortOrder")
      end

      def validate_operation(operation:, field_name:)
        values = MemexProjectChart::Operation.values.collect(&:serialize)
        return if values.include?(operation)

        record.errors.add(
          attribute,
          "'#{field_name}' must be one of: #{values.to_sentence(last_word_connector: ', or ')}"
        )
      end

      def validate_columns_array(columns:, field_name:)
        return unless columns
        unless columns.is_a?(Array)
          record.errors.add(attribute, "'#{field_name}' must be an array")
          return
        end
        unless columns.all? { |c| c.is_a?(Integer) }
          record.errors.add(attribute, "'#{field_name}' must be an array of integers")
        end
      end

      def validate_time
        time = value["time"]
        return unless time

        period = time["period"]
        unless MemexProjectChart::TIME_PERIODS.include?(period)
          record.errors.add(
            attribute,
            "'time.period' must be one of: #{MemexProjectChart::TIME_PERIODS.join(", ")}"
          )
        end

        if period == "custom"
          validate_required_date(date_string: time["startDate"], field_name: "time.startDate")
          validate_required_date(date_string: time["endDate"], field_name: "time.endDate")
        else
          # Ignore date fields for non-custom periods
          value["time"].delete("startDate")
          value["time"].delete("endDate")
        end
      end

      def validate_required_date(date_string:, field_name:)
        unless date_string&.match(DATE_REGEX)
          record.errors.add(
            attribute,
            "'#{field_name}' must be in the format YYYY-MM-DD"
          )
        end
      end
    end
    # This subclass is private because it is an implementation detail of how this
    # validator works and not intended to be accessed from outside the validator
    private_constant :ValidationTarget
  end
end
