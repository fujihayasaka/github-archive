# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class RepositoryAdvisoriesQuery < Base
        QUALIFIER_SEVERITY = :severity
        QUALIFIER_ECOSYSTEM = :ecosystem
        QUALIFIER_PACKAGE = :package
        QUALIFIER_SORT = :sort

        QUALIFIERS = [
          QUALIFIER_SEVERITY,
          QUALIFIER_ECOSYSTEM,
          QUALIFIER_PACKAGE,
          QUALIFIER_SORT,
        ].freeze

        SEVERITY_MAPPING = {
          "low" => "low",
          "medium" => "moderate",
          "moderate" => "moderate",
          "high" => "high",
          "critical" => "critical",
        }.freeze

        SORT_MAPPING = {
          "newest" => :newest,
          "oldest" => :oldest,
          "severity" => :severity,
        }.freeze

        ECOSYSTEM_MAPPING = {
          "npm" => "npm",
          "pip" => "pip",
          "rubygems" => "rubygems",
          "maven" => "maven",
          "nuget" => "nuget",
          "composer" => "composer",
          "go" => "go",
          "rust" => "rust",
          "pub" => "pub",
          "swift" => "swift",
          "actions" => "actions",
        }.freeze

        class << self
          def default_query
            ""
          end

          def parse_and_normalize(query_string)
            return {} if query_string.blank?

            hash = parse(query_string)

            if hash[QUALIFIER_SEVERITY].present?
              hash[QUALIFIER_SEVERITY].map! { |sev| SEVERITY_MAPPING[sev.downcase] }.compact!
              hash.delete(QUALIFIER_SEVERITY) if hash[QUALIFIER_SEVERITY].empty?
            end

            if hash[QUALIFIER_ECOSYSTEM].present?
              hash[QUALIFIER_ECOSYSTEM].map! { |eco| ECOSYSTEM_MAPPING[eco.downcase] }.compact!
              hash.delete(QUALIFIER_ECOSYSTEM) if hash[QUALIFIER_ECOSYSTEM].empty?
            end

            if hash[QUALIFIER_PACKAGE].present?
              hash[QUALIFIER_PACKAGE].map!(&:downcase)
            end

            if hash[QUALIFIER_SORT].present?
              hash[QUALIFIER_SORT] = SORT_MAPPING[hash[QUALIFIER_SORT].first.downcase] || :newest
            end

            if hash[literals_key].present?
              hash[:phrase] = hash[literals_key].join(" ")
            end
            hash.delete(literals_key)

            hash
          end

          protected

          def allowed_qualifiers
            QUALIFIERS
          end

          def allowed_duplicate_qualifiers
            []
          end
        end
      end
    end
  end
end
