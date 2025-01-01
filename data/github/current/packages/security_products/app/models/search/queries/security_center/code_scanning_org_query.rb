# typed: true
# frozen_string_literal: true
module Search
  module Queries
    module SecurityCenter
      class CodeScanningOrgQuery < CodeScanningBaseQuery
        QUALIFIER_REPOSITORY = :repo
        QUALIFIER_AUTOFIX = :autofix
        PROPERTIES = Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT

        QUALIFIERS = (
          Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIERS +
          [
            QUALIFIER_REPOSITORY,
            QUALIFIER_AUTOFIX,
            PROPERTIES
          ]).freeze

        class << self
          protected def allowed_qualifiers
            QUALIFIERS
          end
        end

        def is_valid?
          return false unless super
          return false unless has_valid_autofix?
          true
        end

        def autofix
          get_values_for_qualifier(QUALIFIER_AUTOFIX).last
        end

        def autofix_enum
          autofix.present? ? GitHub::Turboscan.to_autofix_filter(autofix) : nil
        end

        def has_valid_autofix?
          autofix.blank? || autofix_enum.present?
        end

        def repository_names
          @repository_names ||= get_values_for_qualifier(QUALIFIER_REPOSITORY)
        end

        def excluded_repository_names
          @excluded_repository_names ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_REPOSITORY))
        end

        def has_repository?(repo_name)
          repository_names.include?(repo_name.downcase)
        end

        def custom_properties_query_string
          parsed_query = self.class.parse(@raw_query)
          parsed_query = parsed_query.select do |qualifier, _|
            qualifier.match?(Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT)
          end
          self.class.to_s(parsed_query)
        end
      end
    end
  end
end
