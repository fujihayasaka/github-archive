# typed: true
# frozen_string_literal: true

require "turboscan"

module Search
  module Queries
    module SecurityCenter
      class CodeScanningBaseQuery < Search::Queries::SecurityCenter::Base
        QUALIFIER_IS = :is
        QUALIFIER_RULE = :rule
        QUALIFIER_SORT = :sort
        QUALIFIER_SEVERITY = :severity
        QUALIFIER_TAG = :tag
        QUALIFIER_TOOL = :tool
        QUALIFIER_RESOLUTION = :resolution
        QUALIFIER_TEAM = :team
        QUALIFIER_TOPIC = :topic
        QUALIFIER_AUTOFILTER = :autofilter

        QUALIFIERS = [
          QUALIFIER_IS,
          QUALIFIER_RULE,
          QUALIFIER_SORT,
          QUALIFIER_SEVERITY,
          QUALIFIER_TAG,
          QUALIFIER_TOOL,
          QUALIFIER_RESOLUTION,
          QUALIFIER_TEAM,
          QUALIFIER_TOPIC,
          QUALIFIER_AUTOFILTER
        ].freeze

        DISMISSED_VALUES = %w[used-in-tests false-positive wont-fix].freeze

        class << self

          protected

          def allowed_qualifiers
            QUALIFIERS
          end

          def preserve_case
            true
          end
        end

        attr_reader :raw_query

        def initialize(raw_query = "")
          @raw_query = raw_query
        end

        def is_valid?
          return true if raw_query.blank?
          return false if has_conflicting_values?
          return false if self.class.has_qualifiers_without_value?(raw_query)
          return false unless has_valid_alert_state?
          return false unless has_valid_severity?
          return false unless has_valid_resolutions?
          return false unless has_valid_classification?
          true
        end

        def alert_states
          @alert_states ||= get_values_for_qualifier(QUALIFIER_IS)
        end

        def alert_state_enums
          return @alert_state_enums if defined?(@alert_state_enums)

          states = alert_states.map { |alert_state| GitHub::Turboscan.to_alert_state_filter(alert_state) }.compact
          # Disallow the "all" state
          @alert_state_enums = states.reject { |state| state == ::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_ALL }
        end

        def closed?
          alert_state_enums.include?(::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_CLOSED)
        end

        def open?
          alert_state_enums.include?(::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_OPEN)
        end

        def show_all_states?
          alert_state_enums.empty? || (open? && closed?)
        end

        def has_valid_alert_state?
          alert_states.empty? || alert_state_enums.present?
        end

        def sort
          return @sort if defined?(@sort)
          @sort = get_values_for_qualifier(QUALIFIER_SORT).last&.downcase
        end

        def sort_enum
          case sort
          when "created-desc" then :CREATED_DESCENDING
          when "created-asc"  then :CREATED_ASCENDING
          when "updated-desc" then :UPDATED_DESCENDING
          when "updated-asc"  then :UPDATED_ASCENDING
          end
        end

        def severities
          @severities ||= get_values_for_qualifier(QUALIFIER_SEVERITY)
        end

        def severity
          severities.last
        end

        def severity_enums
          return @severity_enums if defined?(@severity_enums)

          @severity_enums = if severities.present?
            severities.map { |severity| GitHub::Turboscan.to_severity(severity) }.compact
          else
            []
          end
        end

        def severity_enum
          severity_enums.last
        end

        def has_valid_severity?
          severities.empty? || severity_enums.present?
        end

        def excluded_severities
          @excluded_severities ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_SEVERITY))
        end

        def excluded_severity_enums
          @excluded_severity_enums ||=
            if excluded_severities.present?
              excluded_severities.map { |s| GitHub::Turboscan.to_severity(s) }.compact
            else
              []
            end
        end

        def has_valid_excluded_severities?
          excluded_severities.blank? || excluded_severity_enums.present?
        end

        def rule_sarif_identifiers
          @rule_sarif_identifiers ||= get_values_for_qualifier(QUALIFIER_RULE)
        end

        def rule_sarif_identifier
          rule_sarif_identifiers.last
        end

        def excluded_rule_sarif_identifiers
          @excluded_rule_sarif_identifiers ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_RULE))
        end

        def tags
          get_values_for_qualifier(QUALIFIER_TAG)
        end

        def excluded_tags
          get_values_for_qualifier(negate_qualifier(QUALIFIER_TAG))
        end

        def tools
          @tools ||= get_values_for_qualifier(QUALIFIER_TOOL)
        end

        def tool
          tools.last
        end

        def excluded_tools
          @excluded_tools ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_TOOL))
        end

        def resolutions
          @resolutions ||= get_values_for_qualifier(QUALIFIER_RESOLUTION)
        end

        def resolution_enums
          return @resolution_enums if defined?(@resolution_enums)

          @resolution_enums = if resolutions.present?
            handle_dismissed_resolution(resolutions)
              .map { |resolution| GitHub::Turboscan.to_resolution_filter(resolution) }
              .compact
          else
            []
          end
        end

        def excluded_resolutions
          @excluded_resolutions ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_RESOLUTION))
        end

        def excluded_resolution_enums
          @excluded_resolution_enums ||=
            if excluded_resolutions.present?
              handle_dismissed_resolution(excluded_resolutions)
                .map { |resolution| GitHub::Turboscan.to_resolution_filter(resolution) }
                .compact
            else
              []
            end
        end

        def has_valid_resolutions?
          resolutions.empty? || resolution_enums.present?
        end

        memoize def team_names
          get_values_for_qualifier(QUALIFIER_TEAM)
        end

        memoize def excluded_team_names
          get_values_for_qualifier(negate_qualifier(QUALIFIER_TEAM))
        end

        memoize def topics
          get_values_for_qualifier(QUALIFIER_TOPIC)
        end

        memoize def excluded_topics
          get_values_for_qualifier(negate_qualifier(QUALIFIER_TOPIC))
        end

        def search_query
          @search_query ||= get_values_for_literals.join(" ")
        end

        def autofilter
          get_values_for_qualifier(QUALIFIER_AUTOFILTER).last
        end

        def classification_enum
          autofilter.present? ? GitHub::Turboscan.to_classification_filter(autofilter) : nil
        end

        def has_valid_classification?
          autofilter.blank? || classification_enum.present?
        end

        # Name of the function is to have consistent signature with Search::Queries::CodeScanningBaseQuery
        def contains_qualifier?(name:)
          self.class.qualifier_exists?(raw_query, name)
        end

        # Name of the function is to have consistent signature with Search::Queries::CodeScanningBaseQuery
        def qualifier_selected?(name:, value:)
          get_values_for_qualifier(name).any? { |val| val.casecmp?(value) }
        end

        # Removes a qualifier/value pair if exists. Adds them otherwise.
        def add_or_remove(qualifier, value)
          self.class.add_or_remove(raw_query, qualifier, value)
        end

        # Replaces value if the qualifier exists. Adds the qualifier/value pair otherwise.
        # Name of the function is to have consistent signature with Search::Queries::CodeScanningBaseQuery
        def replace_qualifier(name:, value:)
          self.class.add_or_replace(raw_query, name, value)
        end

        # Removes the qualifier if it exists with the given value (even if multiselect).
        # Otherwise adds or replaces the qualifier with the given value.
        def toggle_qualifier(name:, value:)
          self.class.toggle_qualifier(raw_query, name, value)
        end

        # Removes a qualifier with all its values
        def remove_qualifier(qualifier)
          self.class.remove_qualifier(raw_query, qualifier)
        end

        # Removes a list of qualifiers and all of their values
        def remove_qualifiers(qualifiers)
          return self.to_s unless qualifiers.is_a?(Array)

          self.class.remove_qualifiers(raw_query, qualifiers)
        end

        # Created to have consistent signature with Search::Queries::CodeScanningBaseQuery
        def remove_qualifier!(name:, value:)
          if value.nil?
            # Remove all the entries for name
            remove_qualifier(name)
          elsif qualifier_selected?(name: name, value: value)
            toggle_qualifier(name: name, value: value)
          end
        end

        def query_string
          self.class.to_s(self.class.parse(raw_query))
        end

        def user_query
          raw_query
        end

        private

        def has_conflicting_values?
          self.class.has_conflicting_values?(raw_query)
        end

        def get_values_for_qualifier(qualifier)
          self.class.get_qualified_values(raw_query, qualifier)
        end

        def get_values_for_literals
          self.class.get_unqualified_values(raw_query)
        end

        def negate_qualifier(qualifier)
          self.class.negate_qualifier(qualifier)
        end

        def handle_dismissed_resolution(resolution_list)
          if resolution_list.include?("dismissed")
            resolution_list.reject! { |item| item == "dismissed" }
            resolution_list.concat(DISMISSED_VALUES).uniq!
          end
          resolution_list
        end
      end
    end
  end
end
