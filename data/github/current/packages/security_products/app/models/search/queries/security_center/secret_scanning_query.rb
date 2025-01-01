# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class SecretScanningQuery < Search::Queries::SecurityCenter::Base

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
        QUALIFIER_RESULTS_CATEGORY = :results
        QUALIFIER_VALIDITY = :validity
        QUALIFIER_BYPASSED = :bypassed
        QUALIFIER_PUBLICLY_LEAKED = :is_publicly_leaked
        QUALIFIER_MULTI_REPOSITORY = :is_multi_repository
        QUALIFIER_ASSIGNEE = :assignee
        QUALIFIER_HAS = :has
        QUALIFIER_NO = :no
        QUALIFIER_CAMPAIGN = :campaign
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
          QUALIFIER_RESULTS_CATEGORY,
          QUALIFIER_VALIDITY,
          QUALIFIER_BYPASSED,
          QUALIFIER_PUBLICLY_LEAKED,
          QUALIFIER_MULTI_REPOSITORY,
          QUALIFIER_ASSIGNEE,
          QUALIFIER_HAS,
          QUALIFIER_NO,
          QUALIFIER_CAMPAIGN,
          PROPERTIES,
        ].freeze

        IS_OPEN = "open"
        IS_CLOSED = "closed"
        NO_STATE = "no_state"

        DEFAULT_SORT_SERVICE_ENUM = GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING
        DEFAULT_SORT_SLUG_VALUE = "created-desc"
        DEFAULT_IS = IS_OPEN

        DEFAULT_RESULTS = "default"
        GENERIC_RESULTS = "generic"
        DEFAULT_RESULTS_CATEGORY = DEFAULT_RESULTS

        RESULTS_CATEGORIES = T.let([DEFAULT_RESULTS, GENERIC_RESULTS], T::Array[String])

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

        PUBLICLY_LEAKED_TRUE_ENUM = 1
        PUBLICLY_LEAKED_STRINGS = %w(false true)
        IS_PUBLICLY_LEAKED_SLUG = "publicly-leaked"

        PUBLICLY_LEAKED_OPTIONS = [
          {
            label: "True",
            qualifier: QUALIFIER_PUBLICLY_LEAKED,
            service_enum: PUBLICLY_LEAKED_TRUE_ENUM,
            slug: "true"
          },
        ]

        PUBLICLY_LEAKED_OPTIONS_BY_SLUG = PUBLICLY_LEAKED_OPTIONS.index_by { |o| o[:slug] }.freeze

        MULTI_REPOSITORY_TRUE_ENUM = 1
        MULTI_REPOSITORY_STRINGS = %w(false true)
        IS_MULTI_REPOSITORY_SLUG = "multi-repository"

        MULTI_REPOSITORY_OPTIONS = [
          {
            label: "True",
            qualifier: QUALIFIER_MULTI_REPOSITORY,
            service_enum: MULTI_REPOSITORY_TRUE_ENUM,
            slug: "true"
          },
        ]

        MULTI_REPOSITORY_OPTIONS_BY_SLUG = MULTI_REPOSITORY_OPTIONS.index_by { |o| o[:slug] }.freeze

        # Mapping for the `has:` qualifier
        HAS_MAPPING = {
          "assignee" => "assignee",
        }.freeze

        # Mapping for the `no:` qualifier
        NO_MAPPING = {
          "assignee" => "assignee",
        }.freeze

        ALERT_STATE_TO_SERVICE_ENUM = {
          IS_OPEN => GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN,
          IS_CLOSED => GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED,
          NO_STATE => GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE
        }

        OVERLOADED_IS_QUALIFIERS = {
          QUALIFIER_PUBLICLY_LEAKED => IS_PUBLICLY_LEAKED_SLUG,
          QUALIFIER_MULTI_REPOSITORY => IS_MULTI_REPOSITORY_SLUG
        }

        CAMPAIGN_STATUSES = {
          open: 1,
          closed: 2,
          none: 3
        }.freeze

        CAMPAIGN_OPTIONS = [
          {
            label: "Open",
            qualifier: QUALIFIER_CAMPAIGN,
            service_enum: CAMPAIGN_STATUSES[:open],
            slug: "open"
          },
          {
            label: "Closed",
            qualifier: QUALIFIER_CAMPAIGN,
            service_enum: CAMPAIGN_STATUSES[:closed],
            slug: "closed"
          },
          {
            label: "None",
            qualifier: QUALIFIER_CAMPAIGN,
            service_enum: CAMPAIGN_STATUSES[:none],
            slug: "none"
          },
        ]

        CAMPAIGN_OPTIONS_BY_SLUG = CAMPAIGN_OPTIONS.index_by { |o| o[:slug] }.freeze
        CAMPAIGN_EXCLUDE_ALL_WILDCARD = "*"
        CAMPAIGN_NONE_TOKEN = "none"
        ALERT_TYPE_SECRET_SCANNING = "secret_scanning"

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

        sig { params(show_results_category_suggestions: T::Boolean).returns(String) }
        def self.default_query(show_results_category_suggestions)
          value = "is:#{DEFAULT_IS}"
          return "#{value} #{QUALIFIER_RESULTS_CATEGORY}:#{DEFAULT_RESULTS}" if show_results_category_suggestions
          value
        end

        sig { returns(String) }
        def self.default_query_generic_results
          value = "is:#{DEFAULT_IS}"
          "#{value} #{QUALIFIER_RESULTS_CATEGORY}:#{GENERIC_RESULTS}"
        end

        def initialize(query: "", allow_results_category: true)
          @query = parse_overloaded_is_qualifiers(query)
          @allow_results_category = allow_results_category
        end

        def parse_overloaded_is_qualifiers(query)
          return "" if query.blank?
          out_query = query.dup
          OVERLOADED_IS_QUALIFIERS.each do |qualifier, slug|
            # matches both the singular and multi-value cases, e.g.:
            # "is:publicly-leaked" => "is_publicly_leaked:true"
            # "is:open,publicly-leaked" => "is_publicly_leaked:true is:open"
            out_query.gsub!(/#{QUALIFIER_IS}:([\w,]*#{slug}[\w,]*)\b/) do
              values = $1.split(",")
              values = values.reject { |value| value == slug }
              values = values.join(",")
              "#{qualifier}:true#{values.present? ? " #{QUALIFIER_IS}:#{values}" : ""}"
            end
          end
          out_query.freeze
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
          return false if negated_alert_states.present?
          return false if resolutions.present? && !has_valid_resolutions?
          return false if has_invalid_results_category?
          return false if validities.present? && !has_valid_validities?
          return false if bypassed.present? && !has_valid_bypassed?
          return false if owner_types.present? && !has_valid_owner_types?
          return false if negated_owner_types.present? && !has_valid_negated_owner_types?
          return false if publicly_leaked.present? && !has_valid_publicly_leaked?
          return false if negated_publicly_leaked.present?
          return false if multi_repository.present? && !has_valid_multi_repository?
          return false if negated_multi_repository.present?
          return false unless has_valid_has?
          return false unless has_valid_no?
          return false if campaigns.present? && !has_campaign_filter?
          return false if negated_campaigns.present? && !has_campaign_filter?
          return false if negated_all_campaign_statuses?
          true
        end

        memoize def alert_states
          get_qualified_values(QUALIFIER_IS)
        end

        memoize def negated_alert_states
          get_negated_values(QUALIFIER_IS)
        end

        memoize def alert_state_enums
          states = alert_states.map { |state| ALERT_STATE_TO_SERVICE_ENUM[state] }.compact
          return [ALERT_STATE_TO_SERVICE_ENUM[NO_STATE]] if states.empty?
          states
        end

        memoize def is_open_page?
          alert_state_enums.include?(ALERT_STATE_TO_SERVICE_ENUM[IS_OPEN])
        end
        alias open? is_open_page?

        memoize def is_closed_page?
          alert_state_enums.include?(ALERT_STATE_TO_SERVICE_ENUM[IS_CLOSED])
        end
        alias closed? is_closed_page?

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

        memoize def publicly_leaked
          get_qualified_values(QUALIFIER_PUBLICLY_LEAKED)
        end

        memoize def negated_publicly_leaked
          get_negated_values(QUALIFIER_PUBLICLY_LEAKED)
        end

        memoize def publicly_leaked_enums
          publicly_leaked.map do |slug|
            PUBLICLY_LEAKED_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def has_valid_publicly_leaked?
          publicly_leaked_enums.any?
        end

        memoize def multi_repository
          get_qualified_values(QUALIFIER_MULTI_REPOSITORY)
        end

        memoize def negated_multi_repository
          get_negated_values(QUALIFIER_MULTI_REPOSITORY)
        end

        memoize def multi_repository_enums
          multi_repository.map do |slug|
            MULTI_REPOSITORY_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def has_valid_multi_repository?
          multi_repository_enums.any?
        end

        memoize def campaigns
          get_qualified_values(QUALIFIER_CAMPAIGN)
        end

        memoize def campaign_enums
          campaigns.map do |slug|
            CAMPAIGN_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end
        memoize def negated_campaign_enums
          negated_campaigns.map do |slug|
            CAMPAIGN_OPTIONS_BY_SLUG[slug]&.dig(:service_enum)
          end.compact
        end

        memoize def campaign_strings
          campaigns
        end

        memoize def negated_campaigns
          get_negated_values(QUALIFIER_CAMPAIGN)
        end

        memoize def negated_campaign_strings
          negated_campaigns
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

        sig { params(results_category_slug: String).returns(String) }
        def get_results_category_href(results_category_slug)
          new_query_string = self.class.add_or_replace(query, QUALIFIER_RESULTS_CATEGORY, results_category_slug)
          self.class.query_string_for_url(new_query_string)
        end

        sig { returns(T.nilable(String)) }
        memoize def results_category
          return nil if !@allow_results_category
          confs = get_qualified_values(QUALIFIER_RESULTS_CATEGORY)
          return DEFAULT_RESULTS if confs.empty?
          T.must(confs.first)
        end

        sig { returns(T::Boolean) }
        memoize def has_invalid_results_category?
          confs = get_qualified_values(QUALIFIER_RESULTS_CATEGORY)
          return !confs.empty? if !@allow_results_category
          return true if confs.length > 1
          return true if !confs.empty? && !RESULTS_CATEGORIES.include?(confs.first)
          false
        end

        sig { returns(T.nilable(String)) }
        memoize def assignee_login
          get_qualified_values(QUALIFIER_ASSIGNEE).first
        end

        sig { returns(T.nilable(String)) }
        memoize def excluded_assignee_login
          get_qualified_values(self.class.negate_qualifier(QUALIFIER_ASSIGNEE)).first
        end

        sig { returns(T.nilable(Integer)) }
        def assigned_user_presence
          has = get_qualified_values(QUALIFIER_HAS)
          return GitHub::Proto::SecretScanning::Api::V2::AssignedUserPresence::ASSIGNED_USER_PRESENCE_HAS_USER if has.include?(HAS_MAPPING["assignee"])

          no = get_qualified_values(QUALIFIER_NO)
          GitHub::Proto::SecretScanning::Api::V2::AssignedUserPresence::ASSIGNED_USER_PRESENCE_NO_USER if no.include?(NO_MAPPING["assignee"])
        end

        sig { returns(T::Boolean) }
        memoize def has_valid_has?
          has = get_qualified_values(QUALIFIER_HAS)
          return true if has.empty?

          Array(has).all? { |h| HAS_MAPPING.values.include?(h) }
        end

        sig { returns(T::Boolean) }
        memoize def has_valid_no?
          no = get_qualified_values(QUALIFIER_NO)
          return true if no.empty?

          Array(no).all? { |n| NO_MAPPING.values.include?(n) }
        end

        sig { returns(T.nilable(String)) }
        def custom_properties_query_string
          parsed_query = self.class.parse(@query)
          parsed_query = parsed_query.select do |qualifier, _|
            qualifier.match?(Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT)
          end
          self.class.to_s(parsed_query)
        end

        memoize def has_campaign_filter?
          campaign_enums.present? || negated_campaign_enums.present?
        end

        memoize def negated_all_campaign_statuses?
          return false if negated_campaign_enums.empty?
          campaign_status_set = CAMPAIGN_STATUSES.values.to_set
          campaign_status_set.subset?(negated_campaign_enums.to_set)
        end

        sig do
          params(
            organization: T.nilable(Organization),
            current_user: User,
            included: T::Array[Integer],
            excluded: T::Array[Integer],
          ).returns(T.nilable(GitHub::Proto::SecretScanning::Api::V2::CampaignFilter))
        end
        def build_campaigns_request(organization:, current_user:, included:, excluded:)
          return nil unless organization
          return nil if included.empty? && excluded.empty?

          included_set = included.to_set
          excluded_set = excluded.to_set

          if included_set.any?
            has_open = included_set.include?(CAMPAIGN_STATUSES[:open])
            has_closed = included_set.include?(CAMPAIGN_STATUSES[:closed])
            has_none = included_set.include?(CAMPAIGN_STATUSES[:none])

            return nil if has_open && has_closed && has_none

            if has_none && !has_open && !has_closed
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                exclude: GitHub::Proto::SecretScanning::Api::V2::CampaignExclude.new(
                  exclude_all: true,
                  campaign_ids: []
                )
              )
            end

            if has_open && has_none && !has_closed
              closed_campaign_ids = get_campaign_ids(organization: organization, current_user: current_user, open: false)
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                exclude: GitHub::Proto::SecretScanning::Api::V2::CampaignExclude.new(
                  campaign_ids: closed_campaign_ids
                )
              )
            end

            if has_closed && has_none && !has_open
              open_campaign_ids = get_campaign_ids(organization: organization, current_user: current_user, open: true)
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                exclude: GitHub::Proto::SecretScanning::Api::V2::CampaignExclude.new(
                  campaign_ids: open_campaign_ids
                )
              )
            end

            target_campaign_ids = []
            if has_open
              target_campaign_ids.concat(get_campaign_ids(organization: organization, current_user: current_user, open: true))
            end
            if has_closed
              target_campaign_ids.concat(get_campaign_ids(organization: organization, current_user: current_user, open: false))
            end

            return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
              include: GitHub::Proto::SecretScanning::Api::V2::CampaignInclude.new(
                campaign_ids: target_campaign_ids.uniq
              )
            )
          end

          if excluded_set.any?
            excludes_open = excluded_set.include?(CAMPAIGN_STATUSES[:open])
            excludes_closed = excluded_set.include?(CAMPAIGN_STATUSES[:closed])
            excludes_none = excluded_set.include?(CAMPAIGN_STATUSES[:none])

            if excludes_none && !excludes_open && !excludes_closed
              all_campaign_ids = get_campaign_ids(organization: organization, current_user: current_user, open: nil)
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                include: GitHub::Proto::SecretScanning::Api::V2::CampaignInclude.new(
                  campaign_ids: all_campaign_ids
                )
              )
            end

            if excludes_none && excludes_closed && !excludes_open
              open_campaign_ids = get_campaign_ids(organization: organization, current_user: current_user, open: true)
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                include: GitHub::Proto::SecretScanning::Api::V2::CampaignInclude.new(
                  campaign_ids: open_campaign_ids
                )
              )
            end

            if excludes_none && excludes_open && !excludes_closed
              closed_campaign_ids = get_campaign_ids(organization: organization, current_user: current_user, open: false)
              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                include: GitHub::Proto::SecretScanning::Api::V2::CampaignInclude.new(
                  campaign_ids: closed_campaign_ids
                )
              )
            end

            if excludes_open || excludes_closed
              excluded_campaign_ids = []
              if excludes_open
                excluded_campaign_ids.concat(get_campaign_ids(organization: organization, current_user: current_user, open: true))
              end
              if excludes_closed
                excluded_campaign_ids.concat(get_campaign_ids(organization: organization, current_user: current_user, open: false))
              end

              return GitHub::Proto::SecretScanning::Api::V2::CampaignFilter.new(
                exclude: GitHub::Proto::SecretScanning::Api::V2::CampaignExclude.new(
                  campaign_ids: excluded_campaign_ids.uniq
                )
              )
            end
          end

          nil
        end

        sig { params(organization: Organization, current_user: User, open: T.nilable(T::Boolean)).returns(T::Array[Integer]) }
        def get_campaign_ids(organization:, current_user:, open: true)
          scope = SecurityCampaigns::SecurityCampaign.where(organization: organization)
          if open == true
            campaigns = scope.open
          elsif open == false
            campaigns = scope.closed
          else
            campaigns = scope.open.or(scope.closed)
          end

          campaigns = campaigns.filter_spam_for(current_user)
          campaigns.for_alert_type(ALERT_TYPE_SECRET_SCANNING).order(:created_at).pluck(:id)
        end
      end
    end
  end
end
