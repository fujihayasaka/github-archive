# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class CodeScanningRepoQuery < CodeScanningBaseQuery
        QUALIFIER_BRANCH = :branch
        QUALIFIER_PR = :pr
        QUALIFIER_REF = :ref
        QUALIFIER_PATH = :path
        QUALIFIER_LANGUAGE = :language

        REF_LIKE_QUALIFIERS = [QUALIFIER_REF, QUALIFIER_BRANCH, QUALIFIER_PR].freeze

        QUALIFIERS = (
          Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIERS +
          [
            QUALIFIER_BRANCH,
            QUALIFIER_PR,
            QUALIFIER_REF,
            QUALIFIER_PATH,
            QUALIFIER_LANGUAGE
          ]
        ).freeze

        class << self
          protected def allowed_qualifiers
            QUALIFIERS
          end
        end

        def is_valid?
          return false unless super
          return false unless has_valid_languages?
          true
        end

        def branches
          get_values_for_qualifier(QUALIFIER_BRANCH)
        end

        def negated_branches
          get_values_for_qualifier(negate_qualifier(QUALIFIER_BRANCH))
        end

        def refs
          get_values_for_qualifier(QUALIFIER_REF)
        end

        def negated_refs
          get_values_for_qualifier(negate_qualifier(QUALIFIER_REF))
        end

        def set_reflike_qualifier(name:, value:)
          new_query_string = remove_qualifiers(REF_LIKE_QUALIFIERS)
          self.class.add_or_remove(new_query_string, name, value)
        end

        def prs
          get_values_for_qualifier(QUALIFIER_PR)
        end

        def security_severity_enum
          severity.present? ? GitHub::Turboscan.to_security_severity(severity) : nil
        end

        def rule_severity_enum
          severity.present? ? GitHub::Turboscan.to_rule_severity(severity) : nil
        end

        def paths
          get_values_for_qualifier(QUALIFIER_PATH)
        end

        def language_paths
          linguist_languages.flat_map do |lang|
            lang&.extensions&.map { |ext| "*#{ext}" } || []
          end
        end

        private

        def has_valid_languages?
          !linguist_languages.include?(nil)
        end

        def linguist_languages
          @linguist_languages ||= get_values_for_qualifier(QUALIFIER_LANGUAGE).map { |lang| Linguist::Language.find_by_name(lang) }
        end
      end
    end
  end
end
