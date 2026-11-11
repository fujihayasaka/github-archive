# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecretScanning
      class CustomPatternsQuery < Search::Queries::SecurityCenter::Base
        QUALIFIER_IS = :is
        QUALIFIER_SORT = :sort
        QUALIFIER_PUSH_PROTECTION = :"push-protection"

        QUALIFIERS = [
          QUALIFIER_IS,
          QUALIFIER_SORT,
          QUALIFIER_PUSH_PROTECTION,
        ].freeze

        DEFAULT_SORT_SERVICE_ENUM = GitHub::Proto::SecretScanning::Api::V3::SortOrder::CREATED_DESCENDING
        DEFAULT_SORT_SLUG_VALUE = "created-desc"

        DEFAULT_STATUS_SERVICE_ENUM = GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::PUBLISHED
        DEFAULT_STATUS_SLUG_VALUE = "published"

        DEFAULT_PUSH_PROTECTION_FILTER_SERVICE_ENUM = GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::INCLUDE_ALL
        DEFAULT_PUSH_PROTECTION_FILTER_SLUG_VALUE = "include-all"

        DEFAULT_QUERY = "is:published,unpublished"

        class << self
          def status_options
            [
              {
                label: "Published",
                qualifier: QUALIFIER_IS,
                service_enum: DEFAULT_STATUS_SERVICE_ENUM,
                slug: DEFAULT_STATUS_SLUG_VALUE
              },
              {
                label: "Unpublished",
                qualifier: QUALIFIER_IS,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::CustomPatternState::UNPUBLISHED,
                slug: "unpublished"
              }
            ]
          end

          def sort_options
            [
              {
                label: "Newest",
                qualifier: QUALIFIER_SORT,
                service_enum: DEFAULT_SORT_SERVICE_ENUM,
                slug: DEFAULT_SORT_SLUG_VALUE
              },
              {
                label: "Oldest",
                qualifier: QUALIFIER_SORT,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::SortOrder::CREATED_ASCENDING,
                slug: "created-asc"
              },
              {
                label: "Recently updated",
                qualifier: QUALIFIER_SORT,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::SortOrder::UPDATED_DESCENDING,
                slug: "updated-desc"
              },
              {
                label: "Name",
                qualifier: QUALIFIER_SORT,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::SortOrder::NAME_ASCENDING,
                slug: "name"
              }
            ]
          end

          def push_protected_filter_options
            [
              {
                label: "All",
                qualifier: QUALIFIER_PUSH_PROTECTION,
                service_enum: DEFAULT_PUSH_PROTECTION_FILTER_SERVICE_ENUM,
                slug: DEFAULT_PUSH_PROTECTION_FILTER_SLUG_VALUE
              },
              {
                label: "Enabled",
                qualifier: QUALIFIER_PUSH_PROTECTION,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::PUSH_PROTECTED,
                slug: "enabled"
              },
              {
                label: "Disabled",
                qualifier: QUALIFIER_PUSH_PROTECTION,
                service_enum: GitHub::Proto::SecretScanning::Api::V3::PushProtectedFilter::NOT_PUSH_PROTECTED,
                slug: "disabled"
              }
            ]
          end

          protected

          def allowed_qualifiers
            QUALIFIERS
          end
        end

        # expose from base so it can be used in validation
        def self.literals_key
          super
        end

        # instance members

        attr_reader :query

        def initialize(query: "")
          @query = query == "" || query.nil? ? DEFAULT_QUERY : query
          is_values = get_qualified_values(QUALIFIER_IS)
          if is_values.length == 0
            @query = set_all_is_values
          end
        end

        def has_default_is_values?
          status.include?("published") && status.include?("unpublished")
        end

        def sort
          @sort ||= get_qualified_values(QUALIFIER_SORT).first
        end

        def status
          @staus ||= get_qualified_values(QUALIFIER_IS)
        end

        def push_protected_filter
          @push_protected_filter ||= get_qualified_values(QUALIFIER_PUSH_PROTECTION).first
        end

        def unqualified_query
          @unqualified_query ||= get_unqualified_values.join(" ")
        end

        def sort_enum
          @sort_enum ||= self.class.sort_options.find { |option| option[:slug] == sort }&.dig(:service_enum) || DEFAULT_SORT_SERVICE_ENUM
        end

        sig { returns(T::Array[Integer]) }
        def status_enum
          @status_enum ||= status.map do |option|
            self.class.status_options.find { |so| so[:slug] == option }&.dig(:service_enum)
          end.compact
        end

        sig { returns(Integer) }
        def push_protected_filter_enum
          @push_protected_filter_enum ||= self.class.push_protected_filter_options.find { |option| option[:slug] == push_protected_filter }&.dig(:service_enum) || DEFAULT_PUSH_PROTECTION_FILTER_SERVICE_ENUM
        end

        private

        def get_qualified_values(qualifier)
          self.class.get_qualified_values(query, qualifier)
        end

        def get_unqualified_values
          self.class.get_unqualified_values(query)
        end

        def set_all_is_values
          self.class.add_or_replace(query, QUALIFIER_IS, %w(published unpublished))
        end

      end
    end
  end
end
