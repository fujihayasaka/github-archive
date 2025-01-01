# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Dashboards
      class Base
        extend T::Helpers
        include GitHub::Memoizer
        include GitHub::RouteHelpers

        OLDEST_ACTIVITY_INSIGHTS_DAYS = 90

        abstract!

        sig { returns(::Organization) }
        attr_reader :owner

        sig { params(owner: ::Organization).void }
        def initialize(owner:)
          @owner = owner
        end

        sig { abstract.returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def payload; end

        sig { returns(String) }
        def csv
          validate_csv_headers

          CSV.generate do |csv|
            csv << human_readable_csv_headers

            flattened_data.each do |row|
              csv_row = csv_headers.map { |header| row[header] }
              csv << csv_row
            end
          end
        end

        sig { overridable.returns(T::Boolean) }
        def should_render?
          true
        end

        sig { abstract.returns(Copilot::Types::MetricsCatalogEntry) }
        def catalog_entry; end

        private

        sig { abstract.returns(T::Array[T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
        def data; end

        sig { abstract.returns(T::Array[Symbol]) }
        def csv_headers; end

        sig { returns(T::Array[String]) }
        def human_readable_csv_headers
          csv_headers.map { |header| header.to_s.underscore.humanize }
        end

        sig { void }
        def validate_csv_headers
          row = flattened_data.first
          return unless row

          csv_headers.each do |header|
            unless row.key?(header)
              raise "CSV header '#{header}' not found in data row: #{row}"
            end
          end
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
        memoize def flattened_data
          data.map do |row|
            flatten_hash(row).transform_keys { |key| key.to_s.camelize(:lower).to_sym }
          end
        end

        sig do
          params(hash: T::Hash[T.untyped, T.untyped], prefix: T.nilable(String)) # rubocop:disable Sorbet/ForbidTUntyped
            .returns(T::Hash[Symbol, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped
        end
        def flatten_hash(hash, prefix = nil)
          hash.each_with_object({}) do |(key, value), result|
            current_key = key.to_s
            new_key = prefix ? "#{prefix}_#{current_key}" : current_key

            if value.is_a?(Hash)
              result.merge!(flatten_hash(value, new_key))
            else
              result[new_key.to_sym] = value
            end
          end.transform_keys { |key| key.to_s.underscore }
        end
      end
    end
  end
end
