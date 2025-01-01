# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class DependabotAlertsQuery < Search::Queries::SecurityCenter::Base
        QUALIFIER_IS = :is
        QUALIFIER_SORT = :sort
        QUALIFIER_MANIFEST = :manifest
        QUALIFIER_PACKAGE = :package
        QUALIFIER_ECOSYSTEM = :ecosystem
        QUALIFIER_HAS = :has
        QUALIFIER_REPOSITORY = :repo
        QUALIFIER_ORGANIZATION = :org
        QUALIFIER_TEAM = :team
        QUALIFIER_TOPIC = :topic
        QUALIFIER_SEVERITY = :severity
        QUALIFIER_RESOLUTION = :resolution
        QUALIFIER_SCOPE = :scope
        QUALIFIER_RELATIONSHIP = :relationship
        QUALIFIER_CUSTOM_PROPERTY = ::Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX
        QUALIFIER_EPSS_PERCENTAGE = :epss_percentage

        QUALIFIERS = [
          QUALIFIER_IS,
          QUALIFIER_SORT,
          QUALIFIER_MANIFEST,
          QUALIFIER_PACKAGE,
          QUALIFIER_ECOSYSTEM,
          QUALIFIER_HAS,
          QUALIFIER_ORGANIZATION,
          QUALIFIER_REPOSITORY,
          QUALIFIER_TEAM,
          QUALIFIER_TOPIC,
          QUALIFIER_SEVERITY,
          QUALIFIER_RESOLUTION,
          QUALIFIER_SCOPE,
          QUALIFIER_RELATIONSHIP,
          QUALIFIER_CUSTOM_PROPERTY,
          QUALIFIER_EPSS_PERCENTAGE,
        ].freeze

        API_QUALIFIERS = [
          QUALIFIER_MANIFEST,
          QUALIFIER_PACKAGE,
          QUALIFIER_ECOSYSTEM,
          QUALIFIER_SEVERITY,
          QUALIFIER_EPSS_PERCENTAGE,
          QUALIFIER_HAS,
          QUALIFIER_SCOPE,
          QUALIFIER_RELATIONSHIP,
        ]

        ALLOWED_DUPLICATE_QUALIFIERS = [
          QUALIFIER_HAS,
        ]

        DEFAULT_QUERY = "is:open"

        STATE_MAPPING = {
          "open" => :open,
          "closed" => :closed,
        }

        # Other has qualifiers like "vulnerable-calls" were planned
        HAS_MAPPING = {
          "patch" => "patch",
        }

        # We want to replace "moderate" with "medium" but until we change the
        # underlying data, we need to massage incoming queries to map "medium"
        # to "moderate."
        SEVERITY_MAPPING = {
          "low" => "low",
          "medium" => "moderate",
          "moderate" => "moderate",
          "high" => "high",
          "critical" => "critical",
        }

        class << self

          # SecurityCenter::Base returns a hash in the format of:
          # { key1: ["val1", "val2"], key2: ["val3"] }
          # This method converts the values of :is and :sort to a symbol,
          # and :phrase to a string that represents the search phrase.
          def parse_and_normalize(query_string, can_sort_by_most_important: false, ignore_sort: false)
            # Dependabot currently only supports ANDing the HAS filter, so if the user
            # tries to input something like ("repo:a repo:b"), we should return a hash
            # with an invalid value here so that the query will return early with no results.
            # Adding support for OR queries to the HAS filter is tracked in
            # https://github.com/github/dependabot-updates/issues/9347
            invalid_query = { QUALIFIER_IS => [:invalid] }
            return invalid_query unless is_valid?(query_string)

            hash = parse(query_string)

            if hash[QUALIFIER_IS].present?
              hash[QUALIFIER_IS].map! do |state|
                STATE_MAPPING[state.downcase]
              end.compact!
              hash[QUALIFIER_IS] = [:invalid] if hash[QUALIFIER_IS].empty?
            end

            if hash[QUALIFIER_HAS].present?
              hash[QUALIFIER_HAS].map! do |state|
                HAS_MAPPING[state.downcase]
              end.compact!
              hash[QUALIFIER_HAS] = [:invalid] if hash[QUALIFIER_HAS].empty?
            end

            if ignore_sort
              hash.delete(QUALIFIER_SORT)
            elsif hash[QUALIFIER_SORT].present?
              mapping = sort_mapping(can_sort_by_most_important:)
              hash[QUALIFIER_SORT] = mapping[hash[QUALIFIER_SORT].first.downcase] || default_sort(can_sort_by_most_important:)
            end

            if hash[QUALIFIER_SEVERITY].present?
              hash[QUALIFIER_SEVERITY].map! do |severity|
                SEVERITY_MAPPING[severity.downcase]
              end.compact!
              hash.delete(QUALIFIER_SEVERITY) if hash[QUALIFIER_SEVERITY].empty?
            end

            if hash[QUALIFIER_RELATIONSHIP].present?
              hash[QUALIFIER_RELATIONSHIP].map! do |relationship|
                relationship.downcase
              end.compact!
              hash.delete(QUALIFIER_RELATIONSHIP) if hash[QUALIFIER_RELATIONSHIP].empty?
            end

            if hash[literals_key].present?
              hash[:phrase] = hash[literals_key].join(" ")
            end

            # The base query parser always returns this key, even if the query
            # string is empty. We don't need it if it doesn't have any values, and
            # if it does, we will store it with the :phrase key instead.
            hash.delete("_literals")
            hash
          end

          sig { params(query_hash: T::Hash[String, T::Array[String]]).returns(T::Hash[String, T::Array[String]]) }
          def custom_properties(query_hash = {})
            query_hash.select { |k| k.match?(QUALIFIER_CUSTOM_PROPERTY) }
          end

          sig { params(query_hash: T::Hash[String, T::Array[String]]).returns(String) }
          def custom_properties_string(query_hash = {})
            custom_properties(query_hash)
              .reduce([]) do |acc, (qualifier, values)|
                output_value = values.map { |value| ::Search::Queries::SecurityCenter::Base.encode_value(value.to_s) }.join(",")
                acc << "#{qualifier}:#{output_value}"
                acc
              end
              .join(" ")
          end

          def sort_mapping(can_sort_by_most_important: false)
            sort_mapping = {
              "newest" => :created_desc,
              "oldest" => :created_asc,
              "severity" => :severity,
              "manifest-path" => :vulnerable_manifest_path,
              "package-name" => :affects,
              "epss-percentage-asc" => :epss_percentage_asc,
              "epss-percentage" => :epss_percentage_desc,
            }

            sort_mapping["most-important"] = :most_important if can_sort_by_most_important
            sort_mapping
          end

          def default_sort(can_sort_by_most_important: false)
            can_sort_by_most_important ? :most_important : :created_desc
          end

          def map_alert_resolution_to_slug_value(alert_resolution)
            option = RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS.find do |option|
              option[:label].casecmp(alert_resolution).zero?
            end
            return unless option.present?

            option[:slug]
          end

          def valid_state?(state)
            return true if state.nil?
            STATE_MAPPING.values.include?(state)
          end

          def valid_has?(has)
            return true if has.nil?
            Array(has).all? { |h| HAS_MAPPING.values.include?(h) }
          end

          # Resolution is valid if it's empty or there is at least one slug
          # value that matches RESOLUTION_OPTIONS or if slug is "auto-dismissed"
          def valid_resolutions?(slugs)
            return true if slugs.blank?
            options = RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS.map { |option| option[:slug] }
            options << "auto-dismissed"
            slugs.any? { |slug| options.include?(slug) }
          end

          def valid_epss_qualifiers?(qualifiers)
            return true if qualifiers.nil? || qualifiers.empty?

            qualifiers.all? { |qualifier| CVEEPSS.valid_query_qualifier?(qualifier) }
          end

          protected

          def allowed_qualifiers
            QUALIFIERS
          end

          sig { override.returns(T::Array[T.any(Symbol, String)]) }
          def allowed_duplicate_qualifiers
            ALLOWED_DUPLICATE_QUALIFIERS
          end

          def preserve_case
            true
          end
        end

        # instance members

        attr_reader :query

        def initialize(query: "")
          @query = query
          @query_hash = self.class.parse_and_normalize(@query)
        end

        # Note: these instance methods are currently used for Insights only
        def is_valid?
          # currently does not support unqualified search - TODO for future
          return false if self.class.get_unqualified_values(@query).any?
          # all qualifiers must have values, ignoring _literals which is always empty
          return false if self.class.has_qualifiers_without_value?(@query)
          # must have valid state and resolutions
          return false unless self.class.valid_state?(@query_hash[QUALIFIER_IS]&.first)
          return false unless self.class.valid_has?(@query_hash[QUALIFIER_HAS])
          return false unless self.class.valid_resolutions?(@query_hash[QUALIFIER_RESOLUTION])
          return false unless self.class.valid_epss_qualifiers?(@query_hash[QUALIFIER_EPSS_PERCENTAGE])

          # remaining cases are covered by the base class
          self.class.is_valid?(@query)
        end

        def repository_names
          @repository_names ||= self.class.get_qualified_values(@query, QUALIFIER_REPOSITORY)
        end

        def excluded_repository_names
          @excluded_repository_names ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_REPOSITORY))
        end

        def alert_states
          @alert_states ||= self.class.get_qualified_values(@query, QUALIFIER_IS)
        end

        def resolutions
          @resolutions ||= self.class.get_qualified_values(@query, QUALIFIER_RESOLUTION)
        end

        def excluded_resolutions
          @excluded_resolutions ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_RESOLUTION))
        end

        def severities
          @severities ||= self.class.get_qualified_values(@query, QUALIFIER_SEVERITY)
        end

        def excluded_severities
          @excluded_severities ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_SEVERITY))
        end

        def scopes
          @scope ||= self.class.get_qualified_values(@query, QUALIFIER_SCOPE)
        end

        def excluded_scopes
          @excluded_scopes ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_SCOPE))
        end

        def relationships
          @relationship ||= self.class.get_qualified_values(@query, QUALIFIER_RELATIONSHIP)
        end

        def excluded_relationships
          @excluded_relationships ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_RELATIONSHIP))
        end

        def ecosystems
          @ecosystems ||= self.class.get_qualified_values(@query, QUALIFIER_ECOSYSTEM)
        end

        def excluded_ecosystems
          @excluded_ecosystems ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_ECOSYSTEM))
        end

        def packages
          @packages ||= self.class.get_qualified_values(@query, QUALIFIER_PACKAGE)
        end

        def excluded_packages
          @excluded_packages ||= self.class.get_qualified_values(@query, self.class.negate_qualifier(QUALIFIER_PACKAGE))
        end
      end
    end
  end
end
