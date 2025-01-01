# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class SecretScanningQuery < Search::Queries::SecurityCenter::Base
        extend T::Sig

        QUALIFIER_IS = :is
        QUALIFIER_PROVIDER = :provider
        QUALIFIER_OWNER = :owner
        QUALIFIER_OWNER_TYPE = :"owner-type"
        QUALIFIER_REPOSITORY = :repo
        QUALIFIER_RESOLUTION = :resolution
        QUALIFIER_SECRET_TYPE = :"secret-type"
        QUALIFIER_SORT = :sort
        QUALIFIER_TEAM = :team
        QUALIFIER_TOPIC = :topic
        QUALIFIER_CONFIDENCE = :confidence
        QUALIFIER_VALIDITY = :validity
        QUALIFIER_BYPASSED = :bypassed
        PROPERTIES = Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT


        QUALIFIERS = [
          QUALIFIER_IS,
          QUALIFIER_PROVIDER,
          QUALIFIER_OWNER,
          QUALIFIER_OWNER_TYPE,
          QUALIFIER_REPOSITORY,
          QUALIFIER_RESOLUTION,
          QUALIFIER_SECRET_TYPE,
          QUALIFIER_SORT,
          QUALIFIER_TEAM,
          QUALIFIER_TOPIC,
          QUALIFIER_CONFIDENCE,
          QUALIFIER_VALIDITY,
          QUALIFIER_BYPASSED,
          PROPERTIES,
        ].freeze

        IS_OPEN = "open"
        IS_CLOSED = "closed"
        NO_STATE = "no_state"

        DEFAULT_SORT_SERVICE_ENUM = GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING
        DEFAULT_SORT_SLUG_VALUE = "created-desc"
        DEFAULT_IS = IS_OPEN

        HIGH_CONFIDENCE = "high"
        OTHER_CONFIDENCE = "other"
        DEFAULT_CONFIDENCE = HIGH_CONFIDENCE

        CONFIDENCES = T.let([HIGH_CONFIDENCE, OTHER_CONFIDENCE], T::Array[String])

        RESOLUTION_OPTIONS = [
          {
            label: "Revoked",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED,
            slug: "revoked"
          },
          {
            label: "False positive",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE,
            slug: "false-positive"
          },
          {
            label: "Used in tests",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
            slug: "used-in-tests"
          },
          {
            label: "Won't fix",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX,
            slug: "wont-fix"
          },
          {
            label: "Custom pattern edited",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_EDITED,
            slug: "pattern-edited",
            feature: :custom_pattern,
          },
          {
            label: "Custom pattern deleted",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_DELETED,
            slug: "pattern-deleted",
            feature: :custom_pattern,
          },
          {
            label: "Ignored by configuration",
            qualifier: QUALIFIER_RESOLUTION,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::HIDDEN_BY_CONFIG,
            slug: "hidden-by-config",
          }

        ]

        RESOLUTION_OPTIONS_BY_SLUG = RESOLUTION_OPTIONS.index_by { |o| o[:slug] }.freeze

        VALIDITY_OPTIONS = [
          {
            label: "Active",
            qualifier: QUALIFIER_VALIDITY,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE,
            slug: "active"
          },
          {
            label: "Inactive",
            qualifier: QUALIFIER_VALIDITY,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE,
            slug: "inactive"
          },
          {
            label: "Unknown",
            qualifier: QUALIFIER_VALIDITY,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN,
            slug: "unknown"
          },
        ]

        VALIDITY_OPTIONS_BY_SLUG = VALIDITY_OPTIONS.index_by { |o| o[:slug] }.freeze

        OWNER_TYPE_OPTIONS = [
          {
            label: "Organization",
            qualifier: QUALIFIER_OWNER_TYPE,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::BusinessSelector::OwnerType::OWNER_TYPE_ORGANIZATION,
            slug: "organization"
          },
          {
            label: "User",
            qualifier: QUALIFIER_OWNER_TYPE,
            service_enum: GitHub::Proto::SecretScanning::Api::V2::BusinessSelector::OwnerType::OWNER_TYPE_USER,
            slug: "user"
          },
        ]

        OWNER_TYPE_OPTIONS_BY_SLUG = OWNER_TYPE_OPTIONS.index_by { |o| o[:slug] }.freeze

        BYPASSED_TRUE_ENUM = 1
        BYPASSED_STRINGS = %w(false true)

        BYPASSED_OPTIONS = [
          {
            label: "True",
            qualifier: QUALIFIER_BYPASSED,
            service_enum: BYPASSED_TRUE_ENUM,
            slug: "true"
          },
        ]

        BYPASSED_OPTIONS_BY_SLUG = BYPASSED_OPTIONS.index_by { |o| o[:slug] }.freeze

        ALERT_STATE_TO_SERVICE_ENUM = {
          IS_OPEN => GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN,
          IS_CLOSED => GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED,
          NO_STATE => GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE
        }

        class << self
          def get_service_enums_from_slug_values(query_string = "", qualifier, options)
            service_enums = []
            slug_values_in_query = get_qualified_values(query_string, qualifier).to_set

            options.each do |option|
              next unless slug_values_in_query.include?(option[:slug])
              service_enums << option[:service_enum]
            end

            service_enums
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
                service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_ASCENDING,
                slug: "created-asc"
              },
              {
                label: "Recently updated",
                qualifier: QUALIFIER_SORT,
                service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_DESCENDING,
                slug: "updated-desc"
              },
              {
                label: "Least recently updated",
                qualifier: QUALIFIER_SORT,
                service_enum: GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_ASCENDING,
                slug: "updated-asc"
              }
            ]
          end

          protected

          def allowed_qualifiers
            QUALIFIERS
          end
        end

        # instance members

        attr_reader :query

        sig { params(show_confidence_suggestions: T::Boolean).returns(String) }
        def self.default_query(show_confidence_suggestions)
          value = "is:#{DEFAULT_IS}"
          return "#{value} confidence:#{DEFAULT_CONFIDENCE}" if show_confidence_suggestions
          value
        end

        sig { returns(String) }
        def self.default_query_low_confidence
          value = "is:#{DEFAULT_IS}"
          "#{value} confidence:#{OTHER_CONFIDENCE}"
        end

        def initialize(query: "", allow_confidence: true)
          @query = query
          @allow_confidence = allow_confidence
        end

        def is_valid?
          # empty search is always valid
          return true if query.blank?
          # does not support unqualified search
          return false if self.class.get_unqualified_values(query).any?
          # does not support AND filters
          return false if self.class.has_duplicate_qualifiers?(query)
          # all qualifiers must have values, ignoring _literals which is always empty
          return false if self.class.has_qualifiers_without_value?(query)

          # any qualifier with known/constrained values can be statically validated
          return false if !has_valid_alert_state?
          return false if resolutions.present? && !has_valid_resolutions?
          return false if has_invalid_confidence?
          return false if validities.present? && !has_valid_validities?
          return false if bypassed.present? && !has_valid_bypassed?
          return false if owner_types.present? && !has_valid_owner_types?
          return false if negated_owner_types.present? && !has_valid_negated_owner_types?
          true
        end

        memoize def alert_states
          get_qualified_values(QUALIFIER_IS)
        end

        memoize def alert_state_enums
          states = alert_states.map { |state| ALERT_STATE_TO_SERVICE_ENUM[state] }.compact
          return [ALERT_STATE_TO_SERVICE_ENUM[NO_STATE]] if states.empty?
          states
        end

        memoize def is_open_page?
          alert_state_enums.include?(ALERT_STATE_TO_SERVICE_ENUM[IS_OPEN])
        end

        memoize def is_closed_page?
          alert_state_enums.include?(ALERT_STATE_TO_SERVICE_ENUM[IS_CLOSED])
        end

        memoize def is_no_state_page?
          alert_state_enums == [ALERT_STATE_TO_SERVICE_ENUM[NO_STATE]] || (is_open_page? && is_closed_page?)
        end

        memoize def has_valid_alert_state?
          alert_states.all? { |alert_state| ALERT_STATE_TO_SERVICE_ENUM[alert_state].present? }
        end

        def get_is_state_query_string(state_slug)
          self.class.add_or_replace(query, QUALIFIER_IS, state_slug)
        end

        def get_is_state_href(state_slug)
          self.class.query_string_for_url(self.get_is_state_query_string(state_slug))
        end

        memoize def owners
          get_qualified_values(QUALIFIER_OWNER)
        end

        memoize def negated_owners
          get_negated_values(QUALIFIER_OWNER)
        end

        # only above repository level
        memoize def repository_names
          get_qualified_values(QUALIFIER_REPOSITORY)
        end

        memoize def negated_repository_names
          get_negated_values(QUALIFIER_REPOSITORY)
        end

        memoize def team_names
          get_qualified_values(QUALIFIER_TEAM)
        end

        memoize def negated_team_names
          get_negated_values(QUALIFIER_TEAM)
        end

        memoize def topics
          get_qualified_values(QUALIFIER_TOPIC)
        end

        memoize def negated_topics
          get_negated_values(QUALIFIER_TOPIC)
        end

        memoize def secret_types
          get_qualified_values(QUALIFIER_SECRET_TYPE)
        end

        memoize def negated_secret_types
          get_negated_values(QUALIFIER_SECRET_TYPE)
        end

        memoize def owner_types
          get_qualified_values(QUALIFIER_OWNER_TYPE)
        end

        memoize def owner_types_enums
          owner_types.map do |slug|
            OWNER_TYPE_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def owner_types_strings
          owner_types_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::BusinessSelector::OwnerType.lookup(enum).to_s
          end.compact
        end

        memoize def has_valid_owner_types?
          owner_types_enums.any?
        end

        memoize def negated_owner_types
          get_negated_values(QUALIFIER_OWNER_TYPE)
        end

        memoize def negated_owner_types_enums
          negated_owner_types.map do |slug|
            OWNER_TYPE_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def negated_owner_types_strings
          negated_owner_types_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::BusinessSelector::OwnerType.lookup(enum).to_s
          end.compact
        end

        memoize def has_valid_negated_owner_types?
          negated_owner_types_enums.any?
        end

        memoize def secret_providers
          get_qualified_values(QUALIFIER_PROVIDER).map { |provider| provider.gsub("_", " ") }
        end

        memoize def negated_secret_providers
          get_negated_values(QUALIFIER_PROVIDER).map { |provider| provider.gsub("_", " ") }
        end

        memoize def resolutions
          get_qualified_values(QUALIFIER_RESOLUTION)
        end

        memoize def resolutions_enums
          resolutions.map do |slug|
            RESOLUTION_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def resolutions_strings
          resolutions_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::Token::Resolution.lookup(enum).to_s
          end.compact
        end

        memoize def has_valid_resolutions?
          resolutions_enums.any?
        end

        memoize def negated_resolutions
          get_negated_values(QUALIFIER_RESOLUTION)
        end

        memoize def negated_resolutions_enums
          negated_resolutions.map do |slug|
            RESOLUTION_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def negated_resolutions_strings
          negated_resolutions_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::Token::Resolution.lookup(enum).to_s
          end.compact
        end

        memoize def validities
          get_qualified_values(QUALIFIER_VALIDITY)
        end

        memoize def validities_enums
          validities.map do |slug|
            VALIDITY_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def validities_strings
          validities_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::TokenValidity.lookup(enum).to_s
          end.compact
        end

        memoize def has_valid_validities?
          validities_enums.any?
        end

        memoize def negated_validities
          get_negated_values(QUALIFIER_VALIDITY)
        end

        memoize def negated_validities_enums
          negated_validities.map do |slug|
            VALIDITY_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def negated_validities_strings
          negated_validities_enums.map do |enum|
            GitHub::Proto::SecretScanning::Api::V2::TokenValidity.lookup(enum).to_s
          end.compact
        end

        memoize def bypassed
          get_qualified_values(QUALIFIER_BYPASSED)
        end

        memoize def bypassed_enums
          bypassed.map do |slug|
            BYPASSED_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def bypassed_strings
          bypassed_enums.map do |enum|
            BYPASSED_STRINGS[enum]
          end.compact
        end

        memoize def has_valid_bypassed?
          bypassed_enums.any?
        end

        memoize def negated_bypassed
          get_negated_values(QUALIFIER_BYPASSED)
        end

        memoize def negated_bypassed_enums
          negated_bypassed.map do |slug|
            BYPASSED_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def negated_bypassed_strings
          negated_bypassed_enums.map do |enum|
            BYPASSED_STRINGS[enum]
          end.compact
        end

        memoize def sort
          get_qualified_values(QUALIFIER_SORT).first
        end

        memoize def sort_enum
          self.class.sort_options.find { |option| option[:slug] == sort }&.dig(:service_enum) || DEFAULT_SORT_SERVICE_ENUM
        end

        sig { params(qualifier: Symbol).returns(T::Array[String]) }
        def get_qualified_values(qualifier)
          self.class.get_qualified_values(query, qualifier)
        end

        def get_negated_values(qualifier)
          self.class.get_qualified_values(query, self.class.negate_qualifier(qualifier))
        end

        sig { params(confidence_slug: String).returns(String) }
        def get_confidence_href(confidence_slug)
          new_query_string = self.class.add_or_replace(query, QUALIFIER_CONFIDENCE, confidence_slug)
          self.class.query_string_for_url(new_query_string)
        end

        sig { returns(T.nilable(String)) }
        memoize def confidence
          return nil if !@allow_confidence
          confs = get_qualified_values(QUALIFIER_CONFIDENCE)
          return DEFAULT_CONFIDENCE if confs.empty?
          T.must(confs.first)
        end

        sig { returns(T::Boolean) }
        memoize def has_invalid_confidence?
          confs = get_qualified_values(QUALIFIER_CONFIDENCE)
          return !confs.empty? if !@allow_confidence
          return true if confs.length > 1
          return true if !confs.empty? && !CONFIDENCES.include?(confs.first)
          false
        end

        sig { returns(T.nilable(String)) }
        def custom_properties_query_string
          parsed_query = self.class.parse(@query)
          parsed_query = parsed_query.select do |qualifier, _|
            qualifier.match?(Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT)
          end
          self.class.to_s(parsed_query)
        end
      end
    end
  end
end
