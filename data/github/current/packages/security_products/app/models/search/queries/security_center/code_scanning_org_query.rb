# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class CodeScanningOrgQuery < CodeScanningBaseQuery
        QUALIFIER_REPOSITORY = :repo
        QUALIFIER_AUTOFIX = :autofix
        QUALIFIER_CAMPAIGN = :campaign
        PROPERTIES = Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT

        QUALIFIERS = (
          Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIERS +
          [
            QUALIFIER_REPOSITORY,
            QUALIFIER_AUTOFIX,
            QUALIFIER_CAMPAIGN,
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
          return false unless has_valid_campaign?
          return false unless has_valid_excluded_campaign?
          true
        end

        def autofix
          get_values_for_qualifier(QUALIFIER_AUTOFIX)
        end

        def autofix_enum
          autofix.map { |a| a.present? ? GitHub::Turboscan.to_autofix_filter(a) : nil }.compact
        end

        def has_valid_autofix?
          autofix.empty? || autofix_enum.present?
        end

        def excluded_autofix
          get_values_for_qualifier(negate_qualifier(QUALIFIER_AUTOFIX))
        end

        def excluded_autofix_enum
          excluded_autofix.map { |a| a.present? ? GitHub::Turboscan.to_autofix_filter(a) : nil }.compact
        end

        def has_valid_excluded_autofix?
          excluded_autofix.empty? || excluded_autofix_enum.present?
        end

        sig { returns(T::Array[String]) }
        def campaign
          get_values_for_qualifier(QUALIFIER_CAMPAIGN)
        end

        sig { returns(T::Array[Integer]) }
        def campaign_enum
          campaign.map { |c| c.present? ? GitHub::Turboscan.to_security_campaign_state(c) : nil }.compact
        end

        sig { returns(T::Boolean) }
        def has_valid_campaign?
          campaign.empty? || campaign_enum.present?
        end

        sig { returns(T::Array[String]) }
        def excluded_campaign
          get_values_for_qualifier(negate_qualifier(QUALIFIER_CAMPAIGN))
        end

        sig { returns(T::Array[Integer]) }
        def excluded_campaign_enum
          excluded_campaign.map { |c| c.present? ? GitHub::Turboscan.to_security_campaign_state(c) : nil }.compact
        end

        sig { returns(T::Boolean) }
        def has_valid_excluded_campaign?
          excluded_campaign.empty? || excluded_campaign_enum.present?
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
